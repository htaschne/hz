use std::fs;
use std::fs::File;
use std::io::BufReader;
use std::io::BufWriter;
use std::path::Path;
use std::path::PathBuf;
use std::time::SystemTime;
use std::time::UNIX_EPOCH;

use crate::error::NativeError;

use super::stream::compress_stream;
use super::stream::decompress_stream;
use super::stream::CompressionStats;
use super::stream::DecompressionStats;

pub fn compress_file(
    source: impl AsRef<Path>,
    destination: impl AsRef<Path>,
) -> Result<CompressionStats, NativeError> {
    let source = source.as_ref();
    let destination = destination.as_ref();
    validate_distinct_paths(source, destination)?;

    let input =
        File::open(source).map_err(|_| NativeError::Internal("failed to open source file"))?;
    let mut input = BufReader::new(input);
    let temporary = temporary_destination(destination)?;
    let result = (|| {
        let output = File::create(&temporary)
            .map_err(|_| NativeError::Internal("failed to create temporary destination file"))?;
        let mut output = BufWriter::new(output);
        let stats = compress_stream(&mut input, &mut output)?;
        use std::io::Write;
        output
            .flush()
            .map_err(|_| NativeError::Internal("failed to flush destination file"))?;
        Ok(stats)
    })();

    finish_temporary_destination(result, &temporary, destination)
}

pub fn decompress_file(
    source: impl AsRef<Path>,
    destination: impl AsRef<Path>,
) -> Result<DecompressionStats, NativeError> {
    let source = source.as_ref();
    let destination = destination.as_ref();
    validate_distinct_paths(source, destination)?;

    let input =
        File::open(source).map_err(|_| NativeError::Internal("failed to open source file"))?;
    let mut input = BufReader::new(input);
    let temporary = temporary_destination(destination)?;
    let result = (|| {
        let output = File::create(&temporary)
            .map_err(|_| NativeError::Internal("failed to create temporary destination file"))?;
        let mut output = BufWriter::new(output);
        let stats = decompress_stream(&mut input, &mut output)?;
        use std::io::Write;
        output
            .flush()
            .map_err(|_| NativeError::Internal("failed to flush destination file"))?;
        Ok(stats)
    })();

    finish_temporary_destination(result, &temporary, destination)
}

fn validate_distinct_paths(source: &Path, destination: &Path) -> Result<(), NativeError> {
    if source == destination {
        return Err(NativeError::InvalidArgument(
            "source and destination paths must differ",
        ));
    }

    Ok(())
}

fn temporary_destination(destination: &Path) -> Result<PathBuf, NativeError> {
    let directory = destination.parent().unwrap_or_else(|| Path::new("."));
    let filename = destination
        .file_name()
        .and_then(|name| name.to_str())
        .ok_or(NativeError::InvalidArgument(
            "destination path must have a valid file name",
        ))?;
    let unique = SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .map_err(|_| NativeError::Internal("failed to create temporary destination path"))?
        .as_nanos();
    Ok(directory.join(format!(".{filename}.{unique}.tmp")))
}

fn finish_temporary_destination<T>(
    result: Result<T, NativeError>,
    temporary: &Path,
    destination: &Path,
) -> Result<T, NativeError> {
    match result {
        Ok(stats) => {
            fs::rename(temporary, destination)
                .map_err(|_| NativeError::Internal("failed to move temporary destination file"))?;
            Ok(stats)
        }
        Err(error) => {
            let _ = fs::remove_file(temporary);
            Err(error)
        }
    }
}
