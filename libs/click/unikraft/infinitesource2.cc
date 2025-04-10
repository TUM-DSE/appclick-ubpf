/*
 * infinitesource.{cc,hh} -- element generates configurable infinite stream
 * of packets
 * Eddie Kohler
 *
 * Copyright (c) 1999-2000 Massachusetts Institute of Technology
 * Copyright (c) 2006 Regents of the University of California
 * Copyright (c) 2011 Eddie Kohler
 *
 * Permission is hereby granted, free of charge, to any person obtaining a
 * copy of this software and associated documentation files (the "Software"),
 * to deal in the Software without restriction, subject to the conditions
 * listed in the Click LICENSE file. These conditions include: you must
 * preserve this copyright notice, and you cannot mention the copyright
 * holders in advertising related to the Software without their permission.
 * The Software is provided WITHOUT ANY WARRANTY, EXPRESS OR IMPLIED. This
 * notice is a summary of the Click LICENSE file; the license in that file is
 * legally binding.
 */

#include <click/config.h>
#include "infinitesource2.hh"
#include <click/args.hh>
#include <click/error.hh>
#include <click/router.hh>
#include <click/standard/scheduleinfo.hh>
#include <click/glue.hh>
#include <click/straccum.hh>
#include <click/handlercall.hh>
#include <clicknet/ip.h>
#include <clicknet/udp.h>
CLICK_DECLS

InfiniteSource2::InfiniteSource2()
    : _packet(0), _task(this), _end_h(0)
{
}

void *
InfiniteSource2::cast(const char *n)
{
    if (strcmp(n, class_name()) == 0)
	return static_cast<Element *>(this);
    else if (strcmp(n, Notifier::EMPTY_NOTIFIER) == 0)
	return static_cast<Notifier *>(this);
    else
	return 0;
}

int
InfiniteSource2::configure(Vector<String> &conf, ErrorHandler *errh)
{
    ActiveNotifier::initialize(Notifier::EMPTY_NOTIFIER, router());
    String data = "Random bullshit in a packet, at least 64 bytes long. Well, now it is.";
    counter_t limit = -1;
    int burstsize = 1;
    int datasize = -1;
    bool active = true, stop = false, timestamp = true;
    HandlerCall end_h;

    if (Args(conf, this, errh)
	.read_p("DATA", data)
    // .read_mp("SRCETH", EtherAddressArg(), _ethh.ether_shost)
    .read_mp("SRCIP", _sipaddr)
    // .read_mp("DSTETH", EtherAddressArg(), _ethh.ether_dhost)
    .read_mp("DSTIP", _dipaddr)
	.read_p("LIMIT", limit)
	.read_p("BURST", burstsize)
	.read_p("ACTIVE", active)
	.read("TIMESTAMP", timestamp)
	.read("LENGTH", datasize)
	.read("DATASIZE", datasize) // deprecated
	.read("STOP", stop)
	.read("END_CALL", HandlerCallArg(HandlerCall::writable), end_h)
	.complete() < 0)
	return -1;
    if (burstsize < 1)
	return errh->error("burst size must be >= 1");
    if (stop && end_h)
	return errh->error("END_CALL and STOP are mutually exclusive");

    // _ethh.ether_type = htons(0x0800);
    _data = data;
    _datasize = datasize;
    _limit = limit;
    _burstsize = burstsize;
    _count = 0;
    _active = active;
    _timestamp = timestamp;
    delete _end_h;
    if (end_h)
	_end_h = new HandlerCall(end_h);
    else if (stop)
	_end_h = new HandlerCall("stop");
    else
	_end_h = 0;

    setup_packet();

    return 0;
}

int
InfiniteSource2::initialize(ErrorHandler *errh)
{
    if (output_is_push(0)) {
	ScheduleInfo::initialize_task(this, &_task, errh);
	_nonfull_signal = Notifier::downstream_full_signal(this, 0, &_task);
    }
    if (_end_h && _end_h->initialize_write(this, errh) < 0)
	return -1;
    return 0;
}

void
InfiniteSource2::cleanup(CleanupStage)
{
    if (_packet)
	_packet->kill();
    delete _end_h;
}

bool
InfiniteSource2::run_task(Task *)
{
    if (!_active || !_nonfull_signal)
	return false;
    int n = _burstsize;
    if (_limit >= 0 && _count + n >= (ucounter_t) _limit)
	n = (_count > (ucounter_t) _limit ? 0 : _limit - _count);
    for (int i = 0; i < n; i++) {
	Packet *p = _packet->clone();
	if (_timestamp)
	    p->timestamp_anno().assign_now();
	output(0).push(p);
    }
    _count += n;
    if (n > 0)
	_task.fast_reschedule();
    else if (_end_h && _limit >= 0 && _count >= (ucounter_t) _limit)
	(void) _end_h->call_write();
    return n > 0;
}

Packet *
InfiniteSource2::pull(int)
{
    if (!_active) {
    done:
	if (Notifier::active())
	    sleep();
	return 0;
    }
    if (_limit >= 0 && _count >= (ucounter_t) _limit) {
	if (_end_h)
	    (void) _end_h->call_write();
	goto done;
    }
    _count++;
    Packet *p = _packet->clone();
    if (_timestamp)
	p->timestamp_anno().assign_now();
    return p;
}

void
InfiniteSource2::setup_packet()
{
    if (_packet)
	_packet->kill();

    size_t pkt_len;
	if (_datasize < 0) {
        pkt_len = _data.length();
	} else {
	    pkt_len = _datasize;
	}
	pkt_len += 14; // account for ethernet header

    WritablePacket *q = Packet::make(pkt_len);
    _packet = q;
    // memcpy(q->data(), &_ethh, 14);
    click_ip *ip = reinterpret_cast<click_ip *>(q->data()+14);
    click_udp *udp = reinterpret_cast<click_udp *>(ip + 1);

    // set up IP header
    ip->ip_v = 4;
    ip->ip_hl = sizeof(click_ip) >> 2;
    ip->ip_len = htons(pkt_len-14);
    ip->ip_id = 0;
    ip->ip_p = IP_PROTO_UDP;
    ip->ip_src = _sipaddr;
    ip->ip_dst = _dipaddr;
    ip->ip_tos = 0;
    ip->ip_off = 0;
    ip->ip_ttl = 250;
    ip->ip_sum = 0;
    ip->ip_sum = click_in_cksum((unsigned char *)ip, sizeof(click_ip));
    _packet->set_dst_ip_anno(IPAddress(_dipaddr));
    _packet->set_ip_header(ip, sizeof(click_ip));

    // set up UDP header
    udp->uh_sport = (click_random() >> 2) % 0xFFFF;
    udp->uh_dport = (click_random() >> 2) % 0xFFFF;
    udp->uh_sum = 0;
    unsigned short len = pkt_len-14-sizeof(click_ip);
    udp->uh_ulen = htons(len);
    unsigned csum = click_in_cksum((uint8_t *)udp, len);
    udp->uh_sum = click_in_cksum_pseudohdr(csum, ip, len);

    // skip ethernet header (we need to encapsulate after processing)
    size_t skip = 14;
    const void *skipped = _packet->data()+skip;
    _packet = Packet::make(skip, skipped, pkt_len-skip, 0);

    // if (_datasize < 0)
	// _packet = Packet::make(_data.data(), _data.length());
    // else if (_datasize <= _data.length())
	// _packet = Packet::make(_data.data(), _datasize);
    // else {
	// // make up some data to fill extra space
	// StringAccum sa;
	// while (sa.length() < _datasize)
	//     sa << _data;
	// _packet = Packet::make(sa.data(), _datasize);
    // }
}

int
InfiniteSource2::change_param(const String &s, Element *e, void *vparam,
			     ErrorHandler *errh)
{
    InfiniteSource2 *is = (InfiniteSource2 *)e;
    switch ((intptr_t)vparam) {

    case h_data:		// data
	is->_data = s;
	is->setup_packet();
	break;

    case h_limit: {		// limit
	int limit;
	if (!IntArg().parse(s, limit))
	    return errh->error("limit parameter must be integer");
	is->_limit = limit;
	break;
    }

    case h_burst: {		// burstsize
	int burstsize;
	if (!IntArg().parse(s, burstsize) || burstsize < 1)
	    return errh->error("burstsize parameter must be integer >= 1");
	is->_burstsize = burstsize;
	break;
    }

    case h_active: {		// active
	bool active;
	if (!BoolArg().parse(s, active))
	    return errh->error("active parameter must be boolean");
	is->_active = active;
	break;
    }

    case h_reset: {		// reset
	is->_count = 0;
	break;
    }

    case h_length: {		// datasize
	int datasize;
	if (!IntArg().parse(s, datasize))
	    return errh->error("length must be integer");
	is->_datasize = datasize;
	is->setup_packet();
	break;
    }
    }

    if (is->_active
	&& (is->_limit < 0 || is->_count < (ucounter_t) is->_limit)) {
	if (is->output_is_push(0) && !is->_task.scheduled())
	    is->_task.reschedule();
	if (is->output_is_pull(0) && !is->Notifier::active())
	    is->wake();
    }
    return 0;
}

void
InfiniteSource2::add_handlers()
{
    add_data_handlers("data", Handler::f_read | Handler::f_raw | Handler::f_calm, &_data);
    add_write_handler("data", change_param, h_data, Handler::f_raw);
    add_data_handlers("limit", Handler::f_read | Handler::f_calm, &_limit);
    add_write_handler("limit", change_param, h_limit);
    add_data_handlers("burst", Handler::f_read | Handler::f_calm, &_burstsize);
    add_write_handler("burst", change_param, h_burst);
    add_data_handlers("active", Handler::f_read | Handler::CHECKBOX, &_active);
    add_write_handler("active", change_param, h_active);
    add_data_handlers("count", Handler::f_read, &_count);
    add_write_handler("reset", change_param, h_reset, Handler::f_button);
    add_data_handlers("length", Handler::f_read | Handler::f_calm, &_datasize);
    add_write_handler("length", change_param, h_length);
    // deprecated
    add_data_handlers("burstsize", Handler::f_read | Handler::f_calm | Handler::f_deprecated, &_burstsize);
    add_write_handler("burstsize", change_param, h_burst);
    add_data_handlers("datasize", Handler::f_read | Handler::f_calm | Handler::f_deprecated, &_datasize);
    add_write_handler("datasize", change_param, h_length);
    //add_read_handler("notifier", read_param, h_notifier);
    if (output_is_push(0))
	add_task_handlers(&_task, &_nonfull_signal);
}

CLICK_ENDDECLS
EXPORT_ELEMENT(InfiniteSource2)
