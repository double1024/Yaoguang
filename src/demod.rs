//! Small 1090 MHz Mode S pulse-position demodulator for RTL-SDR magnitude samples.

const SAMPLE_RATE_HZ: f64 = 2_400_000.0;
const SAMPLES_PER_US: f64 = SAMPLE_RATE_HZ / 1_000_000.0;
const FRAME_SAMPLES: usize = 288; // (8 us preamble + 112 us payload) × 2.4 MS/s
const CRC24_POLY: u32 = 0x00ff_f409;
const IQ_FULL_SCALE_POWER: f64 = 2.0 * 127.5 * 127.5;

#[derive(Clone, Copy, Debug)]
pub struct DecodedFrame {
    pub bytes: [u8; 14],
    /// Average received IQ power relative to ADC full scale, in dBFS.
    pub signal_dbfs: f32,
}

#[derive(Default)]
pub struct Demodulator {
    power: Vec<f32>,
    scanned: u64,
    valid_crc: u64,
}

impl Demodulator {
    pub fn push_iq(&mut self, iq: &[u8]) -> Vec<DecodedFrame> {
        self.power.reserve(iq.len() / 2);
        for pair in iq.chunks_exact(2) {
            let i = pair[0] as f32 - 127.5;
            let q = pair[1] as f32 - 127.5;
            self.power.push(i * i + q * q);
        }

        if self.power.len() <= FRAME_SAMPLES {
            return Vec::new();
        }

        let mut prefix = Vec::with_capacity(self.power.len() + 1);
        prefix.push(0.0f64);
        for &sample in &self.power {
            prefix.push(prefix.last().copied().unwrap() + sample as f64);
        }

        let mut frames = Vec::new();
        let mut cursor = 0usize;
        while cursor + FRAME_SAMPLES <= self.power.len() {
            self.scanned += 1;
            if !looks_like_preamble(&prefix, cursor) {
                cursor += 1;
                continue;
            }

            if let Some(frame) = decode_frame(&prefix, cursor) {
                self.valid_crc += 1;
                let power = average(&prefix, cursor as f64, (cursor + FRAME_SAMPLES) as f64);
                let dbfs = 10.0 * (power / IQ_FULL_SCALE_POWER).max(1e-12).log10();
                frames.push(DecodedFrame {
                    bytes: frame,
                    signal_dbfs: dbfs as f32,
                });
                cursor += FRAME_SAMPLES;
            } else {
                cursor += 1;
            }
        }

        // Keep enough overlap to finish a frame that straddles the next USB chunk.
        if cursor > 0 {
            self.power.drain(..cursor);
        }
        frames
    }

    pub fn stats(&self) -> (u64, u64) {
        (self.scanned, self.valid_crc)
    }
}

fn area_at(prefix: &[f64], samples: f64) -> f64 {
    let index = samples.floor() as usize;
    let fraction = samples - index as f64;
    if index >= prefix.len() - 1 {
        return *prefix.last().unwrap_or(&0.0);
    }
    prefix[index] + fraction * (prefix[index + 1] - prefix[index])
}

fn average(prefix: &[f64], start: f64, end: f64) -> f64 {
    (area_at(prefix, end) - area_at(prefix, start)) / (end - start)
}

fn us(us: f64) -> f64 {
    us * SAMPLES_PER_US
}

fn looks_like_preamble(prefix: &[f64], sample: usize) -> bool {
    let base = sample as f64;
    let pulse_windows = [(0.0, 0.5), (1.0, 1.5), (3.5, 4.0), (4.5, 5.0)];
    let gap_windows = [(0.5, 1.0), (1.5, 3.5), (4.0, 4.5), (5.0, 8.0)];

    let pulses: [f64; 4] = pulse_windows.map(|(a, b)| average(prefix, base + us(a), base + us(b)));
    let gaps: f64 = gap_windows
        .iter()
        .map(|&(a, b)| average(prefix, base + us(a), base + us(b)) * (b - a))
        .sum::<f64>()
        / 7.0;

    let weakest_pulse = pulses.into_iter().fold(f64::INFINITY, f64::min);
    let strongest_gap = gap_windows
        .iter()
        .map(|&(a, b)| average(prefix, base + us(a), base + us(b)))
        .fold(0.0, f64::max);

    weakest_pulse > 0.0 && weakest_pulse > gaps * 1.8 && weakest_pulse > strongest_gap * 1.25
}

fn decode_frame(prefix: &[f64], sample: usize) -> Option<[u8; 14]> {
    let base = sample as f64 + us(8.0);
    let mut bits = [0u8; 112];
    for (bit_index, bit) in bits.iter_mut().enumerate() {
        let start = base + bit_index as f64 * SAMPLES_PER_US;
        let first = average(prefix, start, start + us(0.5));
        let second = average(prefix, start + us(0.5), start + us(1.0));
        *bit = u8::from(first > second);
    }

    let df = bits[..5].iter().fold(0u8, |value, bit| (value << 1) | bit);
    // This first receiver phase focuses on ADS-B extended squitter only.
    if df != 17 && df != 18 {
        return None;
    }

    let mut frame = [0u8; 14];
    for (index, bit) in bits.iter().enumerate() {
        frame[index / 8] |= bit << (7 - (index % 8));
    }

    if !valid_crc(&frame) {
        return None;
    }
    Some(frame)
}

fn valid_crc(frame: &[u8; 14]) -> bool {
    let mut crc = 0u32;
    for bit_index in 0..88 {
        let bit = ((frame[bit_index / 8] >> (7 - (bit_index % 8))) & 1) as u32;
        let feedback = ((crc >> 23) & 1) ^ bit;
        crc = (crc << 1) & 0x00ff_ffff;
        if feedback != 0 {
            crc ^= CRC24_POLY;
        }
    }
    let parity = ((frame[11] as u32) << 16) | ((frame[12] as u32) << 8) | frame[13] as u32;
    crc == parity
}
