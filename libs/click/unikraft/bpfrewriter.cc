#include <click/config.h>
#include <click/confparse.hh>
#include <click/error.hh>
#include <click/standard/scheduleinfo.hh>
#include <stdio.h>
#include <stdlib.h>

#include "bpfrewriter.hh"

CLICK_DECLS

BPFRewriter::BPFRewriter() {
}

thread_local WritablePacket* _current_packet = nullptr;

void *bpf_packet_add_space(int32_t head, int32_t tail) {
    if (head != 0) {
        if (head > 0) {
            _current_packet = _current_packet->push(head);
        } else {
            _current_packet->pull(-head);
        }
    }

    if (tail != 0) {
        if (tail > 0) {
            _current_packet = _current_packet->put(tail);
        } else {
            _current_packet->take(-tail);
        }
    }

    return _current_packet->data();
}

void BPFRewriter::register_additional_bpf_helpers(void) {
    // TODO: bpf_skb_adjust_room?
    ubpf_register(_ubpf_vm, 60, "bpf_packet_add_space", as_external_function_t((void *) bpf_packet_add_space));
}

void BPFRewriter::push(int, Packet *p) {
    uk_pr_debug("BPFRewriter: Received packet\n");

    WritablePacket * p_out = p->uniqueify();
    if (!p_out) {
        return;
    }

    uk_rwlock_rlock(&_lock);
    _current_packet = p_out;
    int ret = this->exec(p_out);
    p_out = _current_packet;
    uk_rwlock_runlock(&_lock);

    _current_packet = nullptr;

    if (ret == -1) {
        p_out->kill();
        return;
    }

    output(0).push(p_out);
}

CLICK_ENDDECLS
ELEMENT_REQUIRES(int64)

EXPORT_ELEMENT(BPFRewriter)