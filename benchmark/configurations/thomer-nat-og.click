// This Click configuration implements a firewall and NAT, roughly based on the
// mazu-nat.click example.
//
// This example assumes there is one interface that is IP-aliased.  In this
// example, eno1 and eno1:0 have IP addresses 66.68.65.90 and 192.168.1.1,
// respectively.  There is a local network, 192.168.1.0/24, and an upstream
// gateway, 66.58.65.89.  Traffic from the local network is NATed.
//
// Connections can be initiated from the NAT box itself, also.
//
// For bugs, suggestions, and, corrections, please email me.
//
// Author: Thomer M. Gil (click@thomer.com)

define($DEV0 eno1)

AddressInfo(
    eno1-in     192.168.1.1     192.168.1.0/24  3c:ec:ef:62:ad:f2,
    eno1-ex     66.58.65.90                     3c:ec:ef:62:ad:f2,
    gw-addr     10.1.0.2                        3c:ec:ef:62:ad:7d
);


elementclass SniffGatewayDevice {
  $device |
  from :: KernelTun($DEV0)
    -> Print2('Received packet from device')
  //  -> t1 :: Tee
    -> output;
  input -> q :: Queue(1024)
  //  -> t2 :: PullTee
    -> from;
  // t1[1] -> ToHostSniffers;
  // t2[1] -> ToHostSniffers($device);
  ScheduleInfo(from .1, to 1);
}


device :: SniffGatewayDevice($DEV0);
arpq_in :: ARPQuerier(eno1-in) -> ic2 :: AverageCounter() -> device;
ip_to_extern :: GetIPAddress(16)
        -> CheckIPHeader
        -> EtherEncap(0x800, eno1-ex, gw-addr)
        -> ic1 :: AverageCounter()
        -> device;
ip_to_host :: EtherEncap(0x800, gw-addr, eno1-ex)
        // -> ToHost;
        -> Discard;
ip_to_intern :: GetIPAddress(16)
        -> CheckIPHeader
        -> arpq_in;


arp_class :: Classifier(
        12/0806 20/0001,        // [0] ARP requests
        12/0806 20/0002,        // [1] ARP replies to host
        12/0800);               // [2] IP packets

device
-> ic0 :: AverageCounter()
-> arp_class;

// ARP crap
arp_class[0] -> ARPResponder(eno1-in, eno1-ex) -> device;
arp_class[1] -> arp_t :: Tee;
                arp_t[0] -> Discard; // ToHost;
                arp_t[1] -> [1]arpq_in;


// IP packets
arp_class[2] -> Strip(14)
   -> CheckIPHeader
   -> ipclass :: IPClassifier(dst host eno1-ex,
                              dst host eno1-in,
                              src net eno1-in);

// Define pattern NAT
iprw :: IPRewriterPatterns(NAT eno1-ex 50000-65535 - -);

// Rewriting rules for UDP/TCP packets
// output[0] rewritten to go into the wild
// output[1] rewritten to come back from the wild or no match
rw :: IPRewriter(pattern NAT 0 1,
                 pass 1);

// Rewriting rules for ICMP packets
irw :: ICMPPingRewriter(pass);
irw[0] -> ip_to_extern;
irw[1] -> icmp_me_or_intern :: IPClassifier(dst host eno1-ex, -);
          icmp_me_or_intern[0] -> ip_to_host;
          icmp_me_or_intern[1] -> ip_to_intern;

// Rewriting rules for ICMP error packets
ierw :: ICMPRewriter(rw irw);
ierw[0] -> icmp_me_or_intern;
ierw[1] -> icmp_me_or_intern;


// Packets directed at eno1-ex.
// Send it through IPRewriter(pass).  If there was a mapping, it will be
// rewritten such that dst is eno1-in:net, otherwise dst will still be for
// eno1-ex.
ipclass[0] -> [1]rw;

// packets that were rewritten, heading into the wild world.
rw[0] -> ip_to_extern;

// packets that come back from the wild or are not part of an established
// connection.
rw[1] -> established_class :: IPClassifier(dst host eno1-ex,
                                           dst net eno1-in);

         // not established yet or returning packets for a connection that was
         // established from this host itself.
         established_class[0] ->
           firewall :: IPClassifier(dst tcp port ssh,
                                    dst tcp port smtp,
                                    dst tcp port domain,
                                    dst udp port domain,
                                    icmp type echo-reply,
                                    proto icmp,
                                    port > 4095,
                                    -);

                                    firewall[0] -> ip_to_host; // ssh
                                    firewall[1] -> ip_to_host; // smtp
                                    firewall[2] -> ip_to_host; // domain (t)
                                    firewall[3] -> ip_to_host; // domain (u)
                                    firewall[4] -> [0]irw;     // icmp reply
                                    firewall[5] -> [0]ierw;    // other icmp
                                    firewall[6] -> ip_to_host; // port > 4095, probably for connection
                                                               // originating from host itself
                                    firewall[7] -> Discard;    // don't allow incoming for port <= 4095

        // established connection
        established_class[1] -> ip_to_intern;

// To eno1-in.  Only accept from inside network.
ipclass[1] -> IPClassifier(src net eno1-in) -> ip_to_host;

// Packets from eno1-in:net either stay on local network or go to the wild.
// Those that go into the wild need to go through the appropriate rewriting
// element.  (Either UDP/TCP rewriter or ICMP rewriter.)
ipclass[2] -> inter_class :: IPClassifier(dst net eno1-in, -);
              inter_class[0] -> ip_to_intern;
              inter_class[1] -> ip_udp_class :: IPClassifier(tcp or udp,
                                                             icmp type echo);
                                ip_udp_class[0] -> [0]rw;
                                ip_udp_class[1] -> [0]irw;


Script(print "Btw: sleeping first increases startup time.",
       wait 1s,
       label start,
       print "Rx rate: $(ic0.count)   TxExt rate: $(ic1.count)   TxInt rate: $(ic2.count)",
       write ic0.reset,
       write ic1.reset,
       write ic2.reset,
       wait 1s,
       goto start,
)
