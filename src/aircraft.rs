use rs1090::decode::DF;
use rs1090::decode::bds::bds05::Source;
use rs1090::decode::bds::bds09::AirborneVelocitySubType;
use rs1090::prelude::{ME, Message};

pub const FIELD_CALLSIGN: u32 = 1 << 0;
pub const FIELD_SPEED: u32 = 1 << 1;
pub const FIELD_DIRECTION: u32 = 1 << 2;
pub const FIELD_ALTITUDE: u32 = 1 << 3;
pub const FIELD_VERTICAL_RATE: u32 = 1 << 4;
pub const FIELD_SIGNAL: u32 = 1 << 6;

pub const SPEED_GROUND: u8 = 1;
pub const SPEED_AIR: u8 = 2;
pub const DIRECTION_TRACK: u8 = 1;
pub const DIRECTION_MAGNETIC_HEADING: u8 = 2;
pub const ALTITUDE_BAROMETRIC: u8 = 1;
pub const ALTITUDE_GNSS: u8 = 2;

/// A single-message update. `fields` marks which values in this update are valid.
#[repr(C)]
#[derive(Clone, Copy, Debug, Default)]
pub struct AircraftUpdate {
    pub icao24: u32,
    pub fields: u32,
    pub callsign_len: u8,
    pub speed_kind: u8,
    pub direction_kind: u8,
    pub altitude_kind: u8,
    pub speed_kt: f64,
    pub direction_deg: f64,
    pub altitude_ft: i32,
    pub vertical_rate_fpm: i16,
    pub reserved: u16,
    callsign: [u8; 8],
    pub signal_dbfs: f32,
}

impl AircraftUpdate {
    pub fn callsign_bytes(&self) -> &[u8] {
        &self.callsign[..usize::from(self.callsign_len.min(8))]
    }

    pub fn callsign_buffer(&self) -> &[u8; 8] {
        &self.callsign
    }

    pub fn to_english_line(&self) -> String {
        let callsign = std::str::from_utf8(self.callsign_bytes()).unwrap_or("unknown");
        let mut fields = vec![format!("{:06X}", self.icao24)];
        if self.fields & FIELD_CALLSIGN != 0 {
            fields.push(format!("callsign={callsign}"));
        }
        if self.fields & FIELD_SPEED != 0 {
            let name = if self.speed_kind == SPEED_GROUND {
                "ground_speed_kt"
            } else {
                "airspeed_kt"
            };
            fields.push(format!("{name}={:.2}", self.speed_kt));
        }
        if self.fields & FIELD_DIRECTION != 0 {
            let name = if self.direction_kind == DIRECTION_TRACK {
                "track_deg"
            } else {
                "magnetic_heading_deg"
            };
            fields.push(format!("{name}={:.2}", self.direction_deg));
        }
        if self.fields & FIELD_ALTITUDE != 0 {
            let name = if self.altitude_kind == ALTITUDE_BAROMETRIC {
                "barometric_altitude_ft"
            } else {
                "gnss_height_ft"
            };
            fields.push(format!("{name}={}", self.altitude_ft));
        }
        if self.fields & FIELD_VERTICAL_RATE != 0 {
            fields.push(format!("vertical_rate_fpm={}", self.vertical_rate_fpm));
        }
        fields.join(" ")
    }
}

/// Decode the fields carried by this ADS-B message without merging aircraft state.
/// Swift owns the per-ICAO state aggregation and presentation.
pub fn decode_update(
    raw: &[u8; 14],
    message: &Message,
    signal_dbfs: f32,
) -> AircraftUpdate {
    let mut update = AircraftUpdate {
        icao24: (u32::from(raw[1]) << 16) | (u32::from(raw[2]) << 8) | u32::from(raw[3]),
        signal_dbfs,
        ..AircraftUpdate::default()
    };
    update.fields |= FIELD_SIGNAL;

    if let DF::ExtendedSquitterADSB(adsb) = &message.df {
        match &adsb.message {
            ME::BDS08 { inner, .. } => {
                let callsign = inner.callsign.trim();
                if !callsign.is_empty() && callsign.is_ascii() {
                    let bytes = callsign.as_bytes();
                    let length = bytes.len().min(update.callsign.len());
                    update.callsign[..length].copy_from_slice(&bytes[..length]);
                    update.callsign_len = length as u8;
                    update.fields |= FIELD_CALLSIGN;
                }
            }
            ME::BDS05 { inner, .. } => {
                if let Some(altitude) = inner.alt {
                    update.altitude_ft = altitude;
                    update.altitude_kind = match inner.source {
                        Source::Barometric => ALTITUDE_BAROMETRIC,
                        Source::Gnss => ALTITUDE_GNSS,
                    };
                    update.fields |= FIELD_ALTITUDE;
                }
            }
            ME::BDS09(velocity) => {
                if let Some(vertical_rate) = velocity.vertical_rate {
                    update.vertical_rate_fpm = vertical_rate;
                    update.fields |= FIELD_VERTICAL_RATE;
                }
                match &velocity.velocity {
                    AirborneVelocitySubType::GroundSpeedDecoding(data) => {
                        update.speed_kt = data.groundspeed;
                        update.speed_kind = SPEED_GROUND;
                        update.fields |= FIELD_SPEED;
                        update.direction_deg = data.track;
                        update.direction_kind = DIRECTION_TRACK;
                        update.fields |= FIELD_DIRECTION;
                    }
                    AirborneVelocitySubType::AirspeedSubsonic(data) => {
                        if let Some(speed) = data.airspeed {
                            update.speed_kt = f64::from(speed);
                            update.speed_kind = SPEED_AIR;
                            update.fields |= FIELD_SPEED;
                        }
                        if let Some(heading) = data.heading {
                            update.direction_deg = heading;
                            update.direction_kind = DIRECTION_MAGNETIC_HEADING;
                            update.fields |= FIELD_DIRECTION;
                        }
                    }
                    AirborneVelocitySubType::AirspeedSupersonic(data) => {
                        if let Some(speed) = data.airspeed {
                            update.speed_kt = f64::from(speed) * 4.0;
                            update.speed_kind = SPEED_AIR;
                            update.fields |= FIELD_SPEED;
                        }
                        if let Some(heading) = data.heading {
                            update.direction_deg = f64::from(heading);
                            update.direction_kind = DIRECTION_MAGNETIC_HEADING;
                            update.fields |= FIELD_DIRECTION;
                        }
                    }
                    AirborneVelocitySubType::Reserved0(_)
                    | AirborneVelocitySubType::Reserved1(_) => {}
                }
            }
            _ => {}
        }
    }

    update
}
