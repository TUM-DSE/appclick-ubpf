use std::thread;
use click_benchmark::startup_base::{self, Configuration, System};

fn main() {
    let config = Configuration {
        name: "uk-thomer-nat",
        click_configuration: "configurations/thomer-nat.click",
        vm_extra_args: &[],
        system: System::Unikraft,
    };
    // let config = Configuration {
    //     name: "linux-thomer-nat",
    //     click_configuration: "configurations/thomer-nat-og.click",
    //     vm_extra_args: &["DEV0=172.44.0.2/24"],
    //     system: System::Linux,
    // };

    thread::spawn(|| {
        startup_base::send_packet_loop().expect("error in send packet loop");
    });

    let nsec = startup_base::run_benchmark(&config).as_nanos();
    println!("Bench-helper startup time (nsec): {}", nsec);
}
