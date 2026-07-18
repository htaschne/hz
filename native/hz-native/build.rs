use std::path::Path;

fn main() {
    println!("cargo:rerun-if-changed=include/hz_native.h");

    let header = Path::new("include/hz_native.h");
    if !header.exists() {
        panic!("missing public C ABI header: include/hz_native.h");
    }
}
