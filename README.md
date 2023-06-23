# IOTProject
# Project 2. LoraWAN-like sensor networks
Implement and showcase a network architecture similar to LoraWAN in
TinyOS. The requirements of this project are:
1. Create a topology with 5 sensor nodes, 2 gateway nodes and one network server node, as illustrated in Figure 1.
2. Each sensor node periodically transmits (random) data, which is received by one or more gateways. Gateways just forward the received data to the network server.
3. Network server keeps track of the data received by gateways, taking care of removing duplicates. An ACK message is sent back to the
forwarding gateway, which in turn transmits it to the nodes. If a node does not receive an ACK within a 1-second window, the message is
re-transmitted.
4. The network server node should be connected to Node-RED, and periodically transmit data from sensor nodes to Thingspeak through MQTT.
5. Thingspeak must show at least three charts on a public channel.
<img width="325" alt="topology" src="https://github.com/Roberto99-ops/IOTProject/assets/61754160/045c3bf5-aba4-4b31-90d9-9a3059068bc6">

TO CONNECT Cooja to Node-red:
	1.start cooja
	2.start node-red
	3.on cooja: tools->Serial Socket(server)->start
	4.start node-rede simulation
	5.start Cooja simulation
	questa parte funziona, il fatto è che non riesco a non far non comunicare i nodi 2 e 4, quindi li faccio comunicare e i messaggi che si scambiano li butto...
