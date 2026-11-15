use std::ffi::c_char;
use std::ptr;
use std::sync::atomic::{AtomicBool, Ordering};
use std::sync::mpsc::{self, Receiver, Sender, TryRecvError};
use std::sync::{Arc, Mutex};
use std::thread::{self, JoinHandle};

use librtlsdr_rs::RtlSdrDevice;
use rs1090::prelude::Message;

use crate::aircraft::{AircraftUpdate, decode_update};
use crate::demod::{DecodedFrame, Demodulator};

enum WorkerMessage {
    Ready,
    Update(AircraftUpdate),
    Error,
}

/// Opaque receiver session. Create/destroy this only through the exported functions.
pub struct YaoguangHandle {
    updates: Receiver<WorkerMessage>,
    stop: Arc<AtomicBool>,
    last_error: Arc<Mutex<Option<String>>>,
    worker: Option<JoinHandle<()>>,
}

fn open_configured_device() -> Result<RtlSdrDevice, String> {
    let mut sdr = RtlSdrDevice::open(0).map_err(|error| error.to_string())?;
    sdr.set_center_freq(1_090_000_000)
        .map_err(|error| format!("set_center_freq(1090 MHz): {error}"))?;
    sdr.set_sample_rate(2_400_000)
        .map_err(|error| format!("set_sample_rate(2.4 MS/s): {error}"))?;
    sdr.set_tuner_gain_mode(false)
        .map_err(|error| format!("set_tuner_gain_mode(auto): {error}"))?;
    sdr.reset_buffer()
        .map_err(|error| format!("reset_buffer: {error}"))?;
    Ok(sdr)
}

fn record_error(
    message: String,
    sender: &Sender<WorkerMessage>,
    last_error: &Mutex<Option<String>>,
) {
    if let Ok(mut error) = last_error.lock() {
        *error = Some(message);
    }
    let _ = sender.send(WorkerMessage::Error);
}

fn receive_loop(
    sender: Sender<WorkerMessage>,
    stop: Arc<AtomicBool>,
    last_error: Arc<Mutex<Option<String>>>,
) {
    let sdr = match open_configured_device() {
        Ok(device) => device,
        Err(error) => {
            record_error(error, &sender, &last_error);
            return;
        }
    };
    if sender.send(WorkerMessage::Ready).is_err() {
        return;
    }

    let mut demodulator = Demodulator::default();
    for chunk in sdr.iter_samples(262_144) {
        if stop.load(Ordering::Relaxed) {
            break;
        }
        let iq = match chunk {
            Ok(iq) => iq,
            Err(error) => {
                record_error(format!("IQ read: {error}"), &sender, &last_error);
                break;
            }
        };
        for decoded in demodulator.push_iq(&iq) {
            if !process_frame(decoded, &sender, &last_error) {
                return;
            }
        }
    }
}

fn process_frame(
    decoded: DecodedFrame,
    sender: &Sender<WorkerMessage>,
    last_error: &Mutex<Option<String>>,
) -> bool {
    let bytes = decoded.bytes;
    let message = match Message::try_from(bytes.as_slice()) {
        Ok(message) => message,
        Err(error) => {
            record_error(format!("ADS-B parse: {error}"), sender, last_error);
            return true;
        }
    };
    let update = decode_update(&bytes, &message, decoded.signal_dbfs);
    sender.send(WorkerMessage::Update(update)).is_ok()
}

/// Starts a background RTL-SDR receiver. Returns null if a worker thread cannot be created.
/// Device/open errors are reported by `yaoguang_poll_update` and `yaoguang_last_error`.
#[unsafe(no_mangle)]
pub extern "C" fn yaoguang_start() -> *mut YaoguangHandle {
    let (sender, updates) = mpsc::channel();
    let stop = Arc::new(AtomicBool::new(false));
    let last_error = Arc::new(Mutex::new(None));
    let worker_stop = Arc::clone(&stop);
    let worker_error = Arc::clone(&last_error);
    let worker = match thread::Builder::new()
        .name("yaoguang-rtl-sdr".to_owned())
        .spawn(move || receive_loop(sender, worker_stop, worker_error))
    {
        Ok(worker) => worker,
        Err(_) => return ptr::null_mut(),
    };

    Box::into_raw(Box::new(YaoguangHandle {
        updates,
        stop,
        last_error,
        worker: Some(worker),
    }))
}

/// Polls for one decoded message update.
///
/// Returns 2 when the receiver is initialized, 1 for an aircraft update,
/// 0 when the queue is empty, -1 for invalid arguments, and -2 after the receiver
/// reports an error or disconnects. `callsign_buffer`
/// may be null when callsign data is not needed; otherwise it is always NUL-terminated
/// when capacity is greater than zero. The struct's `fields` bitmask identifies valid
/// values. The pointer must be a live handle returned by `yaoguang_start`.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn yaoguang_poll_update(
    handle: *mut YaoguangHandle,
    output: *mut AircraftUpdate,
    callsign_buffer: *mut c_char,
    callsign_capacity: usize,
) -> i32 {
    let Some(handle) = (unsafe { handle.as_ref() }) else {
        return -1;
    };
    if output.is_null() {
        return -1;
    }

    match handle.updates.try_recv() {
        Ok(WorkerMessage::Ready) => 2,
        Ok(WorkerMessage::Update(update)) => {
            unsafe { output.write(update) };
            if !callsign_buffer.is_null() && callsign_capacity > 0 {
                let length = usize::from(update.callsign_len).min(callsign_capacity - 1);
                let source = &update.callsign_buffer()[..length];
                for (index, byte) in source.iter().enumerate() {
                    unsafe { callsign_buffer.add(index).write(*byte as c_char) };
                }
                unsafe { callsign_buffer.add(length).write(0) };
            }
            1
        }
        Ok(WorkerMessage::Error) | Err(TryRecvError::Disconnected) => -2,
        Err(TryRecvError::Empty) => 0,
    }
}

/// Copies the latest receiver error into a caller-owned UTF-8 buffer.
/// Returns the required byte length excluding the NUL terminator.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn yaoguang_last_error(
    handle: *mut YaoguangHandle,
    output: *mut c_char,
    capacity: usize,
) -> usize {
    let Some(handle) = (unsafe { handle.as_ref() }) else {
        return 0;
    };
    let Ok(error) = handle.last_error.lock() else {
        return 0;
    };
    let Some(error) = error.as_deref() else {
        return 0;
    };
    let bytes = error.as_bytes();
    if !output.is_null() && capacity > 0 {
        let length = bytes.len().min(capacity - 1);
        unsafe { ptr::copy_nonoverlapping(bytes.as_ptr(), output.cast::<u8>(), length) };
        unsafe { output.add(length).write(0) };
    }
    bytes.len()
}

/// Stops the receiver and releases the handle. Do not use the pointer after this call.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn yaoguang_stop(handle: *mut YaoguangHandle) {
    if handle.is_null() {
        return;
    }
    let mut handle = unsafe { Box::from_raw(handle) };
    handle.stop.store(true, Ordering::Relaxed);
    if let Some(worker) = handle.worker.take() {
        let _ = worker.join();
    }
}

/// Writes the C header's compile-time ABI version. Included for Swift-side sanity checks.
#[unsafe(no_mangle)]
pub extern "C" fn yaoguang_abi_version() -> u32 {
    3
}
