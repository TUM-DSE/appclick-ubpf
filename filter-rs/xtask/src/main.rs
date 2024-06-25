mod build_ebpf;

use std::process::exit;

use clap::Parser;

#[derive(Debug, Parser)]
pub struct Options {
    #[clap(subcommand)]
    command: Command,
}

#[derive(Debug, Parser)]
enum Command {
    BuildFilterEbpf(build_ebpf::Options),
    BuildRateLimiterEbpf(build_ebpf::Options),
}

fn main() {
    let opts = Options::parse();

    use Command::*;
    let ret = match opts.command {
        BuildFilterEbpf(opts) => build_ebpf::build_ebpf("filter-rs-ebpf", opts),
        BuildRateLimiterEbpf(opts) => build_ebpf::build_ebpf("rate-limiter-ebpf", opts),
    };

    if let Err(e) = ret {
        eprintln!("{e:#}");
        exit(1);
    }
}
