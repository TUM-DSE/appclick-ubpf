#![no_std]
#![no_main]

use aya_ebpf::bpf_printk;
use core::mem;

use bpf_element::BpfContext;
use network_types::eth::EthHdr;

#[no_mangle]
#[link_section = "bpffilter"]
pub extern "C" fn rewrite(ctx: *mut BpfContext) -> u32 {
    let mut ctx = unsafe { *ctx };

    if let Err(_) = try_rewrite(&mut ctx) {
        unsafe {
            bpf_printk!(b"error processing packet\n");
        }
    }

    0
}

#[inline(always)]
fn try_rewrite(ctx: &mut BpfContext) -> Result<(), ()> {
    let ethhdr: &mut EthHdr = unsafe { &mut *ctx.get_ptr_mut(0)? };

    // mirror ethernet source and destination addresses
    let tmp = ethhdr.src_addr;
    ethhdr.src_addr = ethhdr.dst_addr;
    ethhdr.dst_addr = tmp;

    Ok(())
}

#[panic_handler]
fn panic(_info: &core::panic::PanicInfo) -> ! {
    unsafe { core::hint::unreachable_unchecked() }
}
