use std::process::{Child, Command};

pub fn whisker() -> Child {
    const PLOT_WHISKER_PATH: &str = "benches/throughput/plots/plot_whisker.py";
    const SUMMARY_PATH: &str = "target/throughput/summary.json";
    const OUTPUT_PATH: &str = "target/throughput/summary.png";

    Command::new("python3")
        .args(&[PLOT_WHISKER_PATH, SUMMARY_PATH, "--sort-by", "median", "-o", OUTPUT_PATH])
        .spawn()
        .expect("failed to spawn python plotting process")
}