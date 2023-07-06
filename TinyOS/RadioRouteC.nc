 
#include "Timer.h"
#include "printf.h"	
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
  
  message_t queued_packet;
  //Variable to store the message to be sent
  message_t message_to_be_confirmed;
  //this is the list of the last received message for each node. it stores just the last msg_ID for each sensor node 
  //and it works because we assign msg_ID with an increasing number
  int received_messages[5] = {0,0,0,0,0};
  //counter used to build the message ID
  int counter = 1;
  //counter used to limit the max retransmission count of a message
  int n_retr = 0;
  uint16_t queue_addr;
  
  
  bool locked;
  bool ACK_received = FALSE;
  
  bool actual_send (uint16_t address, message_t* packet);
  bool generate_send (uint16_t address, message_t* packet, uint8_t type);
  
  /*
  Function used to prepare the sending of a message distinguishing between data message to be confirmed(type 1) and ACK messages(type 2), 
  adding a random delay(using Timer0) to avoid much possible collisions 
  */
  bool generate_send (uint16_t address, message_t* packet, uint8_t type){
  	uint16_t delay = call Random.rand16();
  	delay = 1 + (delay%400);
  	if (call Timer0.isRunning()){
  		printf("dbg-trying to send but channel busy\n");
  		printfflush();
  		return FALSE;
  	}else{
  	//dbg("radio_send", "generating\n");
  	if (type == 1){
		message_to_be_confirmed = *packet;
  		queued_packet = *packet;
  		queue_addr = address;
  		call Timer0.startOneShot(delay);
  	}else if (type == 2){
  		queued_packet = *packet;
  		queue_addr = address;
  		call Timer0.startOneShot(delay);
  	}
  	}
  	return TRUE;
  }
  
  //When triggered, this function call the actual_send function
  event void Timer0.fired() {
	//dbg("timer", "timer0 fired");
  	actual_send (queue_addr, &queued_packet);
  }
  
  //Function that perform the actual send of the message contained in packet to the address address, using the TinyOS interfaces, obviously onlhy if the channel is not busy
  bool actual_send (uint16_t address, message_t* packet){
	//var used just to build the debug message
	char dbg_message[200];
	int dest;
	if (locked) {
		printf("locked");
		printfflush();
    	return FALSE;
    }
    else {
    	radio_route_msg_t* data_msg = (radio_route_msg_t*)call Packet.getPayload(packet, sizeof(radio_route_msg_t));
		if (call AMSend.send(address, packet, sizeof(radio_route_msg_t)) == SUCCESS) {
				if (data_msg == NULL) {
			return FALSE;
      	}
			locked = TRUE;
			
			//just building the debug message
			sprintf(dbg_message, "message %d from node %d ", data_msg->ID, data_msg->sender);
			if(data_msg->destination==0 && TOS_NODE_ID<6)
				sprintf(dbg_message, "%s BROADCASTED", dbg_message);
			if(TOS_NODE_ID==8)
				sprintf(dbg_message, "%s sent to GATEWAY %d", dbg_message, address);
			if(TOS_NODE_ID==6 || TOS_NODE_ID==7)
				sprintf(dbg_message, "%s sent", dbg_message);
			dest = data_msg->destination;
			if(dest==0) dest=8;
			sprintf(dbg_message, "%s with final destination %d with type %d\n", dbg_message, dest, data_msg->type);
			printf("dbg-%s", dbg_message);
			printfflush();
			
		  return TRUE;
  	} else return FALSE; }
  }
  
  //Event triggered when the app is booted
  event void Boot.booted() {
    printf("dbg-Application booted.\n");
    printfflush();
    call AMControl.start();
  }

  //function triggered when the radio actually starts, in case the radio not correctly starts, it restarts it
  event void AMControl.startDone(error_t err) {
	if (err == SUCCESS) {
      
      //sensor nodes start transmitting periodically random data
      if(TOS_NODE_ID >= 1 && TOS_NODE_ID <=5) {
      	call Timer1.startOneShot(2000);
      	printf("dbg-Radio ON on sensor node with ID %d\n", TOS_NODE_ID);
      	printfflush();
      	} else if(TOS_NODE_ID == 6 || TOS_NODE_ID == 7) {
      	printf("dbg-Radio ON on gateway node with ID %d\n", TOS_NODE_ID);
      	printfflush();
      } else {
      	printf("dbg-Radio ON on server node with ID %d\n", TOS_NODE_ID);
      	printfflush();
      }
    }
    else {
      // if not correctly started, restarts it
      printf("dbg-Radio failed to start, retrying...\n");
      printfflush();
      call AMControl.start();
    }
  }

  //This function handle the stop of the radio
  event void AMControl.stopDone(error_t err) {
    printf("dbg-Radio stopped!\n");
    printfflush();
  }
  
  //This function handle the Timer1 expired events, sending a new data message with a random value and incrementing the counter
  event void Timer1.fired() {
  	//generates the random value
	uint16_t val_to_send = call Random.rand16();
	
	radio_route_msg_t* rrm = (radio_route_msg_t*)call Packet.getPayload(&packet, sizeof(radio_route_msg_t));
	//constraints the random value between 1 and 100
	val_to_send = 1 + (val_to_send%100);
	//dbg("timer","Timer1 fired in node %d at time %s\n", TOS_NODE_ID, sim_time_string());
		ACK_received = FALSE;
		rrm->type = 1;//1=data message, 2=ACK message
		rrm->sender = TOS_NODE_ID;
		rrm->value = val_to_send;
		rrm->ID = counter;
		printf("dbg-Timer1 fired in node %d generating DATA MESSAGE\n", TOS_NODE_ID);
		printfflush();
		generate_send(AM_BROADCAST_ADDR,&packet,1);
		counter++;
  }
  
  //This function handle the ACK_timer expired events, retransmittinge the message in case the max retransmission number hasn't been reached
  event void ACK_timer.fired() {
  	//timer fired if ack not received in 1 second, it waits a random number of seconds before retransmitting the message (stored in message_to_be_confirmed)
  	radio_route_msg_t* data_msg = (radio_route_msg_t*)call Packet.getPayload(&message_to_be_confirmed, sizeof(radio_route_msg_t));
  	printf("dbg-ACK_timer fired, resending\n");
  	printfflush();
  	//limiting number of retransmissions up to 3, for each message
  	n_retr++;
  	if(n_retr <=3){
	  	generate_send(AM_BROADCAST_ADDR,&message_to_be_confirmed,1);
	} else {
		n_retr = 0;
		ACK_received = TRUE;
		call Timer1.startOneShot(2000);
		printf("dbg-Message with ID %d discarded after 3 attempts of sending it\n", data_msg->ID);
		printfflush();
	}
  }

  //This function handle the reciving message events 
  event message_t* Receive.receive(message_t* bufPtr, void* payload, uint8_t len) {
	if (len != sizeof(radio_route_msg_t)) {return bufPtr;}
    else {
        radio_route_msg_t* rrm = (radio_route_msg_t*)call Packet.getPayload(bufPtr, sizeof(radio_route_msg_t));
		//dbg("radio_rec","\n");
		
		//used just to build the debug message
		char dbg_message[200];
		int dest;
		
		//building the debug message
		sprintf(dbg_message, "Received packet %d from node %d ", rrm->ID, rrm->sender);
        //dbg("radio_rec", "Received packet %d from node %d ", rrm->ID, rrm->sender);
        if(TOS_NODE_ID==8 || TOS_NODE_ID<6){
        	sprintf(dbg_message, "%sfrom GATEWAY %d", dbg_message, rrm->gateway);
        	}
        	//dbg("radio_rec","from GATEWAY %d ", TOS_NODE_ID);
        dest = rrm->destination;
        if(dest==0) dest=8;
        sprintf(dbg_message, "%s with final destination %d\n", dbg_message, dest);
        //dbg("radio_rec", "with final destination %d at time %s\n", rrm->destination, sim_time_string());
        printf("dbg-%s", dbg_message);
        printfflush();
        //dbg("radio_pack", ">>>Pack \n \t Payload length %hhu \n", call Packet.payloadLength(bufPtr));
        
        
		//SENSOR NODE (1:5)
		//case 1: the msg is received by a sensor node
		if(TOS_NODE_ID >= 1 && TOS_NODE_ID <= 5) {
			if(rrm->type==2){
				//ID checking
				radio_route_msg_t* msg_stored = (radio_route_msg_t*)call Packet.getPayload(&message_to_be_confirmed, sizeof(radio_route_msg_t));
				printf("dbg-Node %d received an ACK message\n",TOS_NODE_ID);
				printfflush();
				if (rrm->ID == msg_stored->ID && !ACK_received) {
					printf("dbg-Node %d received ACK message for the message with ID: %d\n",TOS_NODE_ID, msg_stored->ID);
					printfflush();
					n_retr = 0;
					call ACK_timer.stop();
					ACK_received = TRUE;
					call Timer1.startOneShot(2000);	
				}
			}				
		} else if(TOS_NODE_ID == 6 || TOS_NODE_ID == 7) {
		//GATEWAY NODE (6-7)
		if(rrm->type == 1) {
			//case 2: a GATEWAY receives a data message, it have to forward it to the server
			rrm->gateway = TOS_NODE_ID;
			//dbg("radio_rec","Gateway %d received a DATA MESSAGE\n",TOS_NODE_ID);
			generate_send(8,bufPtr,1);
		} else {
		//case 3: a GATEWAY receives an ack message, it have to forward it to the addressed sensor node
			//dbg("radio_rec","Gateway %d received an ACK MESSAGE\n",TOS_NODE_ID);
			generate_send(rrm->destination,bufPtr,2);
		}} else {
		//SERVER NODE (8)
		//case 4: receives a data message, checks for duplicates, sends ack back
			int sending_node = rrm->sender;
			//dbg("radio_rec","Server node received a DATA MESSAGE\n");
			//we enter here if the message received is a new one
			if(received_messages[sending_node-1] < rrm->ID) {
				received_messages[sending_node-1] = rrm->ID;
				printf("type:%d, sender:%d, gateway:%d, destination:%d, value:%d, ID:%d\n",rrm->type,rrm->sender,rrm->gateway,rrm->destination,rrm->value,rrm->ID);
       			printfflush();
				}

			rrm->type = 2;
			rrm->destination = rrm->sender;
			rrm->sender = 8;
			rrm->ID = rrm->ID;
			generate_send(rrm->gateway, bufPtr, 2);
		}
		return bufPtr;
    }
  }

  //This event is triggered when a message is actually sent 
  event void AMSend.sendDone(message_t* bufPtr, error_t error) {
	/*  
	* In this function, if the node is a sensor node, it starts a timer of that will be triggered (after 1 second) if 
  	* the node doesn't receive the ack back.
	*/ 
	radio_route_msg_t* rrm = (radio_route_msg_t*)call Packet.getPayload(&queued_packet, sizeof(radio_route_msg_t));
	//dbg("radio_send", "sending\n");
	if (&queued_packet == bufPtr) {
      locked = FALSE;
      if(TOS_NODE_ID >= 1 && TOS_NODE_ID <= 5 && rrm->type==1)
	      call ACK_timer.startOneShot(1000);
      /*dbg("radio_send", "\n");
      dbg("radio_send", "Packet sent");
      dbg_clear("radio_send", " at time %s \n",sim_time_string());
      dbg("radio_send", "\n");*/
    }
  }
}



