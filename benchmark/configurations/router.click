// https://github.com/tbarbette/fastclick/blob/main/conf/router/router-vanilla.click
// Slightly modified to be compatible with Click on Unikraft. Functionality not guaranteed.

/*
 * This file implements a L3 router, but with static ARP replacement
 *
 * It uses only vanilla Click element, the purpose of this file is
 * to compare it against router.click.
 *
 * This router has 4 I/O ports, and is intended to run on a 12 core sytem,
 *  using 3 queues per device to dispatch the traffic on the multiple
 *  cores served by the same device. Note how a change in the number of
 *  cores or queue need a rewrite and a modification of the input and
 *  output lines.
 *
 * The approach taken to support MT in this configuration is to keep
 *  a single routing element, somehow what FastClick would do transparently. * Suprisingly, multiple research paper would use the "duplication
 *  approach", running in fact 3 independent routers (one per multiqueue
 *  set), which leads to good performance but is unfeasible in real
 *  situation where you want accurate statistics, have real-size FIB,
 *  or start playing with state elements such as for NAT.
 *
 * Moreover, to achieve the best througput you would need to pin IRQ of
 *  each queues to the good CPU that will handle the core yourself. A
 *  typical way to do that is to call :
 *    echo CPU > /proc/irq/IRQ_N/smp_affinity
 * In this example you would need to do it 12 times, finding the right
 * IRQ_N by yourself.
 *
 * The FastClick version would not need any reconfiguration to change the
 *  number of cores, queues, or to pin IRQs by yourself. It does not need
 *  any kind of StaticThreadSched elements as the available cores will
 *  be shared among devices as opposed to the 24 used here...
 *
 * A launch line would be :
 *   sudo bin/click -j 12 -a conf/fastclick/router-vanilla.click
 */

//Interfaces are supposed to be :
// eth2, 90:e2:ba:46:f2:d4, 10.1.0.1
// eth3, 90:e2:ba:46:f2:d5, 10.2.0.1
// eth4, 90:e2:ba:46:f2:e0, 10.3.0.1
// eth5, 90:e2:ba:46:f2:e1, 10.4.0.1

define ($method NETMAP)
define ($MTU 1500)
define ($bin 16) //Burst size at input
define ($bout 128) //Burt size at output


tol :: Print("Discard to linux") -> Discard(); //ToHost normally

elementclass Input { $devicea,$ip,$eth |

    FromDevice($devicea) -> Print('Received packet from device') -> [0]

    c0 :: Classifier(    12/0806 20/0001,
                              12/0806 20/0002,
                          12/0800,
                          -);

    // Respond to ARP Query
    c0[0] -> Print("ARP") -> arpress :: ARPResponder($ip $eth);
    arpress[0] -> Print("ARP QUERY") -> [1]output;

    // Deliver ARP responses to ARP queriers as well as Linux.
    t :: Tee(2);
    c0[1] -> Print("Tee") -> t;
    t[0] -> Print("Input to linux") -> [2]output; //To linux
    t[1] -> Print("Arp response") -> [1]output; //Directly output

    //Normal IP tou output 0
    c0[2]  -> [0]output;

    // Unknown ethernet type numbers.
    c0[3] -> Print("Unknown packet type") -> Discard();
}

teth20 :: ThreadSafeQueue() -> ToDevice(0);
teth30 :: ThreadSafeQueue() -> ToDevice(1);
teth40 :: ThreadSafeQueue() -> ToDevice(2);
teth50 :: ThreadSafeQueue() -> ToDevice(3);

input00 :: Input(0, 10.1.0.1, 90:e2:ba:46:f2:d4);

input10 :: Input(1, 10.2.0.1, 90:e2:ba:46:f2:d5);

input20 :: Input(2, 10.3.0.1, 90:e2:ba:46:f2:e0);

input30 :: Input(3, 10.4.0.1, 90:e2:ba:46:f2:e1);

input00[1] -> teth20;

input10[1] -> teth30;

input20[1] -> teth40;

input30[1] -> teth50;

input00[2] -> tol;

input10[2] -> tol;

input20[2] -> tol;

input30[2] -> tol;


// Hand incoming IP packets to the routing table.
// CheckIPHeader checks all the lengths and length fields
// for sanity.
elementclass Ip {  |

    input ->
    Strip(14)
    -> CheckIPHeader(INTERFACES 10.1.0.1/16 10.2.0.1/16 10.3.0.1/16 10.4.0.1/16, VERBOSE true)
    -> [0]rt :: LinearIPLookup(    10.1.0.1/16 0,
                    10.2.0.1/16 1,
                    10.3.0.1/16 2,
                    10.4.0.1/16 3);
    oerror :: Print("ICMP Error : DF") -> [0]rt;
    ttlerror :: Print("ICMP Error : TTL") -> [0]rt;

    // IP packets for this machine.
    // ToHost expects ethernet packets, so cook up a fake header.
    //rt[4] -> EtherEncap(0x0800, 1:1:1:1:1:1, 2:2:2:2:2:2) -> tol;
    rt[0] -> output0 :: IPOutputCombo(1, 10.1.0.1, $MTU);
    rt[1] -> output1 :: IPOutputCombo(2, 10.2.0.1, $MTU);
    rt[2] -> output2 :: IPOutputCombo(3, 10.3.0.1, $MTU);
    rt[3] -> output3 :: IPOutputCombo(4, 10.4.0.1, $MTU);
    rt[4] -> Print("Heu... No out?") -> Discard();

    // DecIPTTL[1] emits packets with expired TTLs.
    // Reply with ICMPs. Rate-limit them?
    output0[3] -> Print("Okh2") ->ICMPError(10.1.0.1, timeexceeded, SET_FIX_ANNO 0) -> ttlerror;
    output1[3] -> ICMPError(10.2.0.1, timeexceeded, SET_FIX_ANNO 0) -> ttlerror;
    output2[3] -> ICMPError(10.3.0.1, timeexceeded, SET_FIX_ANNO 0) -> ttlerror;
    output3[3] -> ICMPError(10.4.0.1, timeexceeded, SET_FIX_ANNO 0) -> ttlerror;

    // Send back ICMP UNREACH/NEEDFRAG messages on big packets with DF set.
    // This makes path mtu discovery work.
    output0[4] -> Print("Okt2") ->ICMPError(10.1.0.1, unreachable, needfrag, SET_FIX_ANNO 0) -> oerror;
    output1[4] -> ICMPError(10.2.0.1, unreachable, needfrag, SET_FIX_ANNO 0) -> oerror;
    output2[4] -> ICMPError(10.3.0.1, unreachable, needfrag, SET_FIX_ANNO 0) -> oerror;
    output3[4] -> ICMPError(10.4.0.1, unreachable, needfrag, SET_FIX_ANNO 0) -> oerror;

    // Send back ICMP Parameter Problem messages for badly formed
    // IP options. Should set the code to point to the
    // bad byte, but that's too hard.
    output0[2] ->Print("Ok2r") -> ICMPError(10.1.0.1, parameterproblem, SET_FIX_ANNO 0) -> oerror;
    output1[2] -> ICMPError(10.2.0.1, parameterproblem, SET_FIX_ANNO 0) -> oerror;
    output2[2] -> ICMPError(10.3.0.1, parameterproblem, SET_FIX_ANNO 0) -> oerror;
    output3[2] -> ICMPError(10.4.0.1, parameterproblem, SET_FIX_ANNO 0) -> oerror;

    // Send back an ICMP redirect if required.
    output0[1] ->Print("Oka2") -> ICMPError(10.1.0.1, redirect, host, SET_FIX_ANNO 0) -> Print("ICMP Error : Redirect") -> [0]output;
    output1[1] -> ICMPError(10.2.0.1, redirect, host, SET_FIX_ANNO 0) -> Print("ICMP Error : Redirect") -> [1]output;
    output2[1] -> ICMPError(10.3.0.1, redirect, host, SET_FIX_ANNO 0) -> Print("ICMP Error : Redirect") -> [2]output;
    output3[1] -> ICMPError(10.4.0.1, redirect, host, SET_FIX_ANNO 0) -> Print("ICMP Error : Redirect") -> [3]output;


    output0[0] -> [0]output;
    output1[0] -> [1]output;
    output2[0] ->  [2]output;
    output3[0] -> [3]output;
}



// An "ARP querier" for each interface.
arpq00 :: EtherEncap(0x0800, 90:e2:ba:46:f2:d4, 00:00:00:11:11:11) -> teth20;
arpq10 :: EtherEncap(0x0800, 90:e2:ba:46:f2:d5, 00:00:00:22:22:22) -> teth30;
arpq20 :: EtherEncap(0x0800, 90:e2:ba:46:f2:e0, 00:00:00:33:33:33) -> teth40;
arpq30 :: EtherEncap(0x0800, 90:e2:ba:46:f2:e1, 00:00:00:44:44:44) -> teth50;


input00[0] -> Paint(1) -> Ip() [0,1,2,3]=> arpq00,arpq10,arpq20,arpq30;

input10[0] -> Paint(2) -> Ip() [0,1,2,3]=> arpq00,arpq10,arpq20,arpq30;

input20[0] -> Paint(3) -> Ip() [0,1,2,3]=> arpq00,arpq10,arpq20,arpq30;

input30[0] -> Paint(4) -> Ip() [0,1,2,3]=> arpq00,arpq10,arpq20,arpq30;
