#ifndef CLICK_BPFILTER_HH
#define CLICK_BPFILTER_HH

#include <click/config.h>
#include <click/deque.hh>
#include <click/element.hh>
#include <click/error.hh>
#include <click/task.hh>
#include <uk/rwlock.h>
#include <bpf_helpers.hh>
#include <ubpf.h>
#include "bpfelement.hh"

CLICK_DECLS

/*
=c

BPFilter([I<keywords> PROGRAM])

=s basicsources

filters packets based on an ebpf program

=d

Drops all packets received on its single input for which the specified ebpf program returns `1`.

Keyword arguments are:

=over 8

=item FILE

String. Required. File name of the ebpf program defining the filter rules.

=h count read-only
Returns the number of processed packets.

=h filtered read-only
Returns the number of filtered packets.

=h reset_count write-only
When written, it resets both the C<count> & C<filtered> counters.

 */
class BPFilter : public BPFElement {
public:

    BPFilter() CLICK_COLD;

    const char *class_name() const override { return "BPFilter"; }

    const char *port_count() const override { return PORTS_1_1; }

    void add_handlers() override CLICK_COLD;

    void push(int, Packet *) override;

private:

    uint64_t _count;
    uint64_t _filtered;

    static int write_handler(const String &, Element *, void *, ErrorHandler *) CLICK_COLD;
};

CLICK_ENDDECLS
#endif