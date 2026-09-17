use serde::Serialize;
use std::io::Read;
use std::path::{Path, PathBuf};

#[derive(Serialize)]
pub struct LocalModel {
    pub name: String,
    pub size_bytes: u64,
    pub available: bool,
    pub detail: String,
}

pub fn valid_name(name: &str) -> bool {
    name.starts_with("ggml-") && name.ends_with(".bin") && name.len() <= 160
        && name.bytes().all(|b| b.is_ascii_alphanumeric() || b"-_.".contains(&b))
        && !name.contains("..")
}

pub fn selected_name(directory: &Path, selected: Option<&str>) -> String {
    selected.map(str::to_owned).unwrap_or_else(|| {
        if directory.join("ggml-base.bin").exists() { "ggml-base.bin" }
        else if directory.join("ggml-large-v3-turbo.bin").exists() { "ggml-large-v3-turbo.bin" }
        else { "ggml-base.bin" }.into()
    })
}

/// Header and size sanity checks, not a checksum or transcription-quality verdict.
pub fn validate(directory: &Path, name: &str) -> Result<PathBuf, String> {
    if !valid_name(name) { return Err("Choose a local ggml model from Control.".into()); }
    let root = directory.canonicalize().map_err(|_| "The local models folder is unavailable.")?;
    let path = root.join(name).canonicalize().map_err(|_| format!("Model {name} is missing. Select an installed model in Control."))?;
    if !path.starts_with(&root) { return Err("The model must stay inside the local models folder.".into()); }
    let mut file = std::fs::File::open(&path).map_err(|e| format!("Cannot read {name}: {e}"))?;
    let metadata = file.metadata().map_err(|e| e.to_string())?;
    if !metadata.is_file() { return Err("The selected model is not a file.".into()); }
    let mut header = [0u8; 56];
    file.read_exact(&mut header).map_err(|_| format!("Model {name} has an incomplete header."))?;
    if &header[..4] != b"lmgg" { return Err(format!("Model {name} is not a ggml Whisper file.")); }
    let fields: Vec<i64> = header[4..].chunks_exact(4)
        .map(|bytes| i32::from_le_bytes(bytes.try_into().unwrap()) as i64).collect();
    if fields[..9].iter().any(|n| *n <= 0) || ![80, 128].contains(&fields[9])
        || fields[10] < 0 || fields[11] <= 0 || fields[12] <= 0 {
        return Err(format!("Model {name} has an invalid Whisper header."));
    }
    let minimum = 56u128 + fields[11] as u128 * fields[12] as u128 * 4
        + fields[0] as u128 * fields[6] as u128 / 2;
    if (metadata.len() as u128) < minimum { return Err(format!("Model {name} is truncated.")); }
    Ok(path)
}

pub fn inventory(directory: &Path) -> Result<Vec<LocalModel>, String> {
    let mut models = Vec::new();
    if !directory.exists() { return Ok(models); }
    for entry in std::fs::read_dir(directory).map_err(|e| e.to_string())? {
        let entry = entry.map_err(|e| e.to_string())?;
        let name = entry.file_name().to_string_lossy().into_owned();
        if !valid_name(&name) { continue; }
        let checked = validate(directory, &name);
        models.push(LocalModel { name, size_bytes: entry.metadata().map(|m| m.len()).unwrap_or(0),
            available: checked.is_ok(), detail: checked.err().unwrap_or_else(|| "Header and size checked".into()) });
    }
    models.sort_by(|a,b| a.name.cmp(&b.name));
    Ok(models)
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::io::Write;
    #[test]
    fn model_selection_rejects_paths_and_detects_missing_corrupt_and_truncated_files() {
        for name in ["../ggml-base.bin", "C:\\ggml-base.bin", "ggml-..bin", "ggml-base.bin:stream", "other.bin"] {
            assert!(!valid_name(name));
        }
        let root = PathBuf::from(env!("CARGO_MANIFEST_DIR")).join("target").join(format!("model-check-{}", std::process::id()));
        std::fs::create_dir_all(&root).unwrap();
        let name = "ggml-test.bin";
        let path = root.join(name);
        assert!(validate(&root, "ggml-missing.bin").is_err());
        let mut file = std::fs::File::create(&path).unwrap();
        file.write_all(b"lmgg").unwrap();
        for field in [100i32, 100, 64, 4, 4, 100, 64, 4, 4, 80, 1, 80, 201] { file.write_all(&field.to_le_bytes()).unwrap(); }
        assert!(validate(&root, name).unwrap_err().contains("truncated"));
        file.set_len(56 + 80 * 201 * 4 + 100 * 64 / 2).unwrap();
        assert!(validate(&root, name).is_ok());
        assert_eq!(inventory(&root).unwrap().len(), 1);
        assert_eq!(selected_name(&root, Some(name)), name);
        assert_eq!(selected_name(&root, None), "ggml-base.bin");
        drop(file);
        std::fs::write(&path, [0u8; 56]).unwrap();
        assert!(!inventory(&root).unwrap()[0].available);
        std::fs::remove_file(path).unwrap();
        std::fs::remove_dir(root).unwrap();
    }
}
