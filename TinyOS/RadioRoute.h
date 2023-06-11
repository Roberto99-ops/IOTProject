

#ifndef RADIO_ROUTE_H
#define RADIO_ROUTE_H

typedef nx_struct radio_route_msg {
	nx_uint8_t type; //1 if data message and 2 if ack message
	nx_uint16_t sender; //sender node
	nx_uint16_t gateway; //sender gateway
	nx_uint16_t destination; //used just by gateways and server
	nx_uint16_t value; //payload
	nx_uint8_t ID;//message ID to check duplicates
} radio_route_msg_t;

enum {
  AM_RADIO_COUNT_MSG = 10,
};

#endif
