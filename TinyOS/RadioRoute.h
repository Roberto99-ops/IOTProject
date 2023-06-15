

#ifndef RADIO_ROUTE_H
#define RADIO_ROUTE_H
//io semplificherei la struttura del messaggio, avere sia gateway che destinatio mi sembra ridondante
//ho capito che il campo gateway lo usi per tenere appunto l'id del gateway che manda il messaggio al server
//che così può mandargli indietro l'ack. però potremmo anche mandare l'ack in broadcast, facendo così 
//saremmo soggetti a meno ritrasmissioni, pensiamoci
typedef nx_struct radio_route_msg {
	nx_uint8_t type; //1 if data message and 2 if ack message
	nx_uint8_t sender; //sender node
	nx_uint8_t gateway; //sender gateway
	nx_uint8_t destination; //used just by gateways and server
	nx_uint16_t value; //payload
	nx_uint16_t ID;//message ID to check for duplicates
} radio_route_msg_t;

enum {
  AM_RADIO_COUNT_MSG = 10,
};

#endif
