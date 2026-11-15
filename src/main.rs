use librtlsdr_rs::RtlSdrDevice;
use rs1090::prelude::Message;
use yaoguang_core::{aircraft::decode_update, demod::Demodulator};

fn main() -> Result<(), Box<dyn std::error::Error>> {
    let mut sdr = RtlSdrDevice::open(0)?;
    println!("Detected tuner: {:?}", sdr.tuner_type());
    sdr.set_center_freq(1_090_000_000)
        .map_err(|e| format!("set_center_freq(1090 MHz): {e}"))?;
    sdr.set_sample_rate(2_400_000)
        .map_err(|e| format!("set_sample_rate(2.4 MS/s): {e}"))?;
    sdr.set_tuner_gain_mode(false)
        .map_err(|e| format!("set_tuner_gain_mode(auto): {e}"))?;
    sdr.reset_buffer()
        .map_err(|e| format!("reset_buffer: {e}"))?;
    println!("Receiving ADS-B on 1090 MHz at 2.4 MS/s; press Ctrl-C to stop.");

    let mut demodulator = Demodulator::default();
    let mut reported_millions = 0u64;
    for chunk in sdr.iter_samples(262_144) {
        let iq = chunk.map_err(|e| format!("IQ read: {e}"))?;
        for decoded in demodulator.push_iq(&iq) {
            let frame = Message::try_from(decoded.bytes.as_slice())
                .map_err(|e| format!("valid-CRC frame parse failed: {e}"))?;
            let update = decode_update(&decoded.bytes, &frame, decoded.signal_dbfs);
            if update.fields & 0x1f != 0 {
                println!("{}", update.to_english_line());
            }
        }
        let (scanned, valid) = demodulator.stats();
        let millions = scanned / 1_000_000;
        if millions > reported_millions {
            reported_millions = millions;
            eprintln!("scanned {scanned} sample positions; {valid} CRC-valid ADS-B frames");
        }
    }
    Ok(())
}
