
/*
*	IMPORTANT:
*	The code will be avaluated based on:
*		Code design  
*
*/
 
 
#include "Timer.h"
#include "RadioRoute.h"


module RadioRouteC @safe() {
  uses {
	interface Boot;
    interface Receive;
    interface AMSend;
    interface Timer<TMilli> as Timer0;
    interface Timer<TMilli> as Timer1;
    interface Timer<TMilli> as ACK_timer;
    interface SplitControl as AMControl;
    interface Packet;
    interface Random;
  }
}
implementation {

  message_t packet;
  //timer0 quando invia
  //timer1 manda periodic messages dai sensori (1-5)
  //bisogna mettere timer2 per rimandare il messaggio indietro con un random 1-3?
  
  // Variables to store the message to send
  message_t queued_packet;
  message_t message_to_be_confirmed;
  //this is the list of the last received message for each node. it stores just the msg_ID and it works because
  //we assign msg_ID with an increasing number with the message that we are sending
  int received_messages[5] = {0,0,0,0,0};
  //counter used fo building the message ID
  int counter = 1;
  uint16_t queue_addr;
  uint16_t time_delays[8]={61,173,267,371,479,583,689,734}; //Time delay in milli seconds
  
  
  bool locked;
  bool ACK_received = FALSE;
  
  bool actual_send (uint16_t address, message_t* packet);
  bool generate_send (uint16_t address, message_t* packet, uint8_t type);
  
  //non so bene dove vadano messe le strutture dati ma per farti capire come le farei io
  //per farla più veloce di potrebbero usare un po di puntatori in modo da dividerla in "zone" a seconda
  //di da dove arriva il messaggio, oppure semplicemente farne 5...ma anche un po sticazzi
  /*typedef struct received_messages{
  	uint16_t id;
  	received_messages_t* next;
  }received_messages_t;
  
  //allora in teoria anche i messaggi inviati dovrebbero avere una lista dinamica,
  //però se vediamo che tendenzialmente gli ack arrivano, possiamo anche fare un vettore 
  //un po grosso e basta, comunque nel caso sarebbe così credo
  typedef struct sent_messages{
  	uint16_t id;
  	sent_messages_t* next;
  }sent_messages_t;*/
  
  
  bool generate_send (uint16_t address, message_t* packet, uint8_t type){
  /*
  * 
  * Function to be used when performing the send after the receive message event.
  * It store the packet and address into a global variable and start the timer execution to schedule the send.
  * It allow the sending of only one message for each REQ and REP type
  * @Input:
  *		address: packet destination address
  *		packet: full packet to be sent (Not only Payload)
  *		type: payload message type
  *
  * MANDATORY: DO NOT MODIFY THIS FUNCTION
  */
  	if (call Timer0.isRunning()){
  		return FALSE;
  	}else{
  	if (type == 1){
		message_to_be_confirmed = *packet;
  		//call ACK_timer.startOneShot(1000);
  		queued_packet = *packet;
  		queue_addr = address;
  		call Timer0.startOneShot(time_delays[TOS_NODE_ID-1]);
  	}else if (type == 2){
  		queued_packet = *packet;
  		queue_addr = address;
  		call Timer0.startOneShot(time_delays[TOS_NODE_ID-1]);
  	}
  	}
  	return TRUE;
  }
  
  event void Timer0.fired() {
  	actual_send (queue_addr, &queued_packet);
  }
  
  bool actual_send (uint16_t address, message_t* packet){
	/*
	* Implement here the logic to perform the actual send of the packet using the tinyOS interfaces
	*/
	if (locked) {
      return FALSE;
    }
    else {
		if (call AMSend.send(address, packet, sizeof(radio_route_msg_t)) == SUCCESS) {
			radio_route_msg_t* data_msg = (radio_route_msg_t*)call Packet.getPayload(packet, sizeof(radio_route_msg_t));
				if (data_msg == NULL) {
			return FALSE;
      	}
			dbg("radio_send", "Sending packet");
			locked = TRUE;
			dbg_clear("radio_send", " at time %s \n", sim_time_string());
			dbg("radio_send","message sent to node %d with type %d\n",address, data_msg->type);
		  return TRUE;
  	} else return FALSE; }
  }
  
  
  event void Boot.booted() {
    dbg("boot","Application booted.\n");
    call AMControl.start();
  }

  event void AMControl.startDone(error_t err) {
	if (err == SUCCESS) {
      
      //if sensor node start transmit periodically random data -> messo ogni 2 secondi, da capire poi se meglio avere tempi diversi per ogni sensore o va bene cosi
      if(TOS_NODE_ID >= 1 && TOS_NODE_ID <=5) {
      	call Timer1.startOneShot(2000);
      	dbg("radio","Radio ON on sensor node with ID %d\n", TOS_NODE_ID);
      	} else if(TOS_NODE_ID == 6 || TOS_NODE_ID == 7) {
      	dbg("radio","Radio ON on gateway node with ID %d\n", TOS_NODE_ID);
      } else {
      	dbg("radio","Radio ON on server node with ID %d\n", TOS_NODE_ID);
      }
    }
    else {
      // if not correctly started restart it
      dbgerror("radio", "Radio failed to start, retrying...\n");
      call AMControl.start();
    }
  }

  event void AMControl.stopDone(error_t err) {
    dbg("boot", "Radio stopped!\n");
  }
  
  event void Timer1.fired() {
	uint16_t val_to_send = call Random.rand16();
	radio_route_msg_t* rrm = (radio_route_msg_t*)call Packet.getPayload(&packet, sizeof(radio_route_msg_t));
	dbg("timer","Timer1 fired in node %d at time %s\n", TOS_NODE_ID, sim_time_string());
		ACK_received = FALSE;
		rrm->type = 1;//1=data message, 2=ACK message
		rrm->sender = TOS_NODE_ID;
		rrm->value = val_to_send;
		rrm->ID = counter;
		dbg("timer","Timer1 fired in node %d generating DATA MESSAGE\n", TOS_NODE_ID);
		generate_send(AM_BROADCAST_ADDR,&packet,1);//in questa func avvio timer di un sec, se non ricevo risposta allora ri-invio mex
		counter++;
  }
  
  event void ACK_timer.fired() {
  	//rimanda mex in message_to_be_confirmed 
  	//deve aspettare un numero random di secondi
  	generate_send(AM_BROADCAST_ADDR,&message_to_be_confirmed,1);//capire se da fare una sola volta o più volte finchè non arriva il suo ack
  }

  event message_t* Receive.receive(message_t* bufPtr, void* payload, uint8_t len) {
  	//radio_route_msg_t* data_msg = (radio_route_msg_t*)call Packet.getPayload(&data_msg_to_send, sizeof(radio_route_msg_t));
	if (len != sizeof(radio_route_msg_t)) {return bufPtr;}
    else {
        radio_route_msg_t* rrm = (radio_route_msg_t*)payload;
		dbg("radio_rec","\n");
        dbg("radio_rec", "Received packet at time %s\n", sim_time_string());
        dbg("radio_pack", ">>>Pack \n \t Payload length %hhu \n", call Packet.payloadLength(bufPtr));
		//SENSOR NODE (1:5)
		//caso 1: ricevuto da sensor node (per forza un ACK ma metto comunque controllo per sicurezza) -> problema da capire quando magari non arriva ACK, si accumulano messaggi o aspetto a inviare altri
		if(TOS_NODE_ID >= 1 && TOS_NODE_ID <= 5 && rrm->type==2) {
			//controllo ID
			radio_route_msg_t* msg_stored = (radio_route_msg_t*)call Packet.getPayload(&message_to_be_confirmed, sizeof(radio_route_msg_t));
			if (rrm->ID == msg_stored->ID && !ACK_received) { //non dovrei controllare nella lista del nodo con un for? questa condizione risulta sempre vera penso
				call ACK_timer.stop();
				ACK_received = TRUE;
				call Timer1.startOneShot(2000);
				//free(message_to_be_confirmed);//se non va lo levo tanto ci sovrascrivo	
			}				
			//si potrebbe anche cancellare il mex salvato ma inutile tanto lo sovrascrivo poi
			//ack_received = TRUE; -> altra possibile sol usare booleano e se FALSE mando di nuovo
		} else if(TOS_NODE_ID == 6 || TOS_NODE_ID == 7) {
		//GATEWAY NODE (6-7)
		if(rrm->type == 1) {
		//caso 2: riceve data message da sensor, deve ri-inviarlo a server node
			rrm->gateway = TOS_NODE_ID;
			generate_send(8,bufPtr,1);
		} else {
		//caso 3: riceve ack da server node, lo inoltra solo all'effettivo destinatario 
			generate_send(rrm->destination,bufPtr,2);
		}} else {
		//SERVER NODE (8)
		//caso 4: riceve data messages da sensor, manda ack, tiene in memoria i mex, controlla i duplicati -> avrà un array dove segna id messaggi ricevuti
			int sending_node = rrm->sender;
			if(received_messages[sending_node-1] < rrm->ID) {
				received_messages[sending_node-1] = rrm->ID;//salviamo solo l'ultimo perchè mandiamo uno per volta
				}
			rrm->type = 2;
			rrm->destination = rrm->sender;
			rrm->sender = 8;
			rrm->ID = rrm->ID;//inutile ma era per far capire che tengo lo stesso
			//capisco se mettere a null ciò che non si usa
			generate_send(rrm->gateway, bufPtr, 2);
		}
    }
  }

  event void AMSend.sendDone(message_t* bufPtr, error_t error) {
	/* This event is triggered when a message is sent 
	*  Check if the packet is sent 
	*/ 
	radio_route_msg_t* rrm = (radio_route_msg_t*)call Packet.getPayload(&queued_packet, sizeof(radio_route_msg_t));
	if (&queued_packet == bufPtr) {
      locked = FALSE;
      if(rrm->type == 1)
	      call ACK_timer.startOneShot(1000);
      dbg("radio_send", "\n");
      dbg("radio_send", "Packet sent");
      dbg_clear("radio_send", " at time %s \n",sim_time_string());
      dbg("radio_send", "\n");
    }
  }
  /*
  //o una roba simile, se teniamo questa struttura guardo bene come si faceva
  bool add_msg_to_list(received_messages_t* first, uint16_t id){
  	while(first->next!=NULL)
  		first = first->next;
  	received_message_t last = malloc(sizeof(received_message_t));
  	last.id = id;
  	last.next = NULL;
  	first->next = last;
  }
  
  bool delete_msg_to_list(received_messages_t* first, uint16_t id){
  	received_messages_t* element = first->next;
  	while(element->id!=id){
  		first = first->next;
  		element = element->next;
  	}
  	first->next = element->next;
  	free(element);
  }
  
  bool check_msg_in_list(received_messages_t* first, uint16_t id){
  	while(first->id!=id){
  		if(first->next==NULL)
  			return FALSE;
  		first = first->next;
  	}
  	return TRUE;
  }*/
}




