# Simple BGP Router

This project will implement a simple BGP router, which will run inside of a provided simulator.

## Overview

First, a network administrator would connect ports to neighboring BGP routers, either from the same Autonomous System (AS) or another AS.
Next, the administrator would configure each of these ports by choosing:

1. The IP address that the router will use on this port
2. Whether this port leads to: a provider, a peer, or a customer (i.e. BGP relationship with neighbor)
3. (Possibly) configure specific routes via each neighbor

Once this configuration is complete, the administrator would turn the router on, and it would contact its neighbors and establish BGP sessions.
At this point, the neighboring routers may pass BGP protocol messages to each other, or data packets from internet users.
The routers job is to:

1. Keep its forwarding table up-to-date, based on the BGP protocol messages it gets from its neighbors
2. Help keep its neighbors' forwarding tables up to date, by sending BGP protocol messages to them
3. Make a best-effort attempt to forward data packets to their correct destination

## Requirements

Instead of real packet formats, data will be sent across the wire in JSON format.

The router must be able to:

- Accept route update messages from the BGP neighbors, and forward updates as appropriate
- Accept route revocation messages from the BGP neighbors, and forward revocations as appropriate
- Forward data packets towards their correct destination
- Return error messages in cases where a data packet cannot be delivered
- Coalesce forwarding table entries for networks that are adjacent and on the same port
- Serialize your forwarding table so that it can be checked for correctness
- Your program must be called *router*

## Simulator

The simulator:

- Creates neighboring routers and the domain sockets which they are connected to
- Runs the router program with the appropriate command line arguments
- Sends various fabricated messages
- Asks the router to dump its forwarding table
- Closes the router

Command Line Spec:

`$ ./sim [-h] [--test-dir <dir>] [--router <router>] <all|[milestone] test-file1 [test-file2] [...]>`

## Command Line Specification

The router program takes one argument, representing the AS number for your router, followed by several arguments representing the "ports" that connect to its neighboring routers.

For each port, the respective command line argument informs your router:

1. What IP address should be assigned to this port
2. The type of relationship your router has with this neighboring router

`./router <asn> <ip.add.re.ss-[peer,prov,cust]> [ip.add.re.ss-[peer,prov,cust]] ...[ip.add.re.ss-[peer,prov,cust]]`

## Messages Format

All messages will have the same basic form:

```json
{
    "src": "<source IP>",
    "dst": "<destination IP>",
    "type": "<update|revoke|data|no route|dump|table>",
    "msg": {...}
}
```

### Route Update Messages

These messages tell your router how to forward data packets to destinations on the internet.

Route announcement messages have the following form:

```json
{
    "src": "<source IP>",
    "dst": "<destination IP>",
    "type": "update",
    "msg":
    {
        "network": "<network prefix>",
        "netmask": "<associated CIDR netmask>",
        "localpref": "<integer>",
        "selfOrigin": "<true|false>",
        "ASPath": "{<nid>, [nid], ...}",
        "origin": "<IGP|EGP|UNK>",
    }
}
```

- The *network* and *netmask* fields describe the network that is routable.
- The *localpref* is the "weight" assigned to this route, where higher weights are better.
- *selfOrigin* describes whether this route was added by the local administrator (true) or not (false), where *true* routes are preferred.
- *ASPath* is the list of Autonomous Systems that the packets along this route will traverse, where preference is given to routes with shorter ASPaths.
- *origin* describes whether this route originated from a router within the local AS (IGP), a remote AS (EGP), or an unknown origin (UNK), where the preference order is IGP > EGP > UNK.
- The last fields of the message are important for breaking ties, when multiple paths to a given destination network are available

Your route announcements must obey the following rules:

- Update received from a customer: send updates to all other neighbors
- Update received from a peer or a provider: only send updates to your customers

### Route Revoke Messages

Sometimes, a neighboring router may need to revoke an announcement.
Typically, this indicates some problem with the route, i.e. it doesn't exist anymore or there has been a hardware failure, so packets can no longer be delivered.
In this case, the neighbor will send a revocation message to your router.

Route revocation messages have the following form:

```json
{
    "src": "<source IP>",
    "dst": "<destination IP>",
    "type": "revoke",
    "msg":
    [
        {"network": "<network prefix>", "netmask": "<associated CIDR netmask>"},
        {"network": "<network prefix>", "netmask": "<associated CIDR netmask>"},
        ...
    ]
}
```

Your route revocations must obey the following rules:

- Revoke received from a customer: send revokes to all other neighbors
- Revoke received from a peer or a provider: only send revokes to your customers

### Data Messages

Data messages have the following format:

```json
{
    "src": "<source IP>",
    "dst": "<destination IP>",
    "type": "data",
    "msg":
    {
        "data": "<some data>"
    }
}
```

**Your router does not care about the *msg* nor its contents**.
Your router only cares about the destination IP address (and possible the source IP address...).

Your router's job is to determine:

1. Which route (if any) in the forwarding table is the best route to use for the given destination IP
2. Whether the data packet is being forwarded legally

#### No Route Available

The router does not have a route to the given destination network.
In this case, your router should return a *no route* message back to the source that sent you the data.

This message has the format:

```json
{
    "src": "<source IP>",
    "dst": "<destination IP>",
    "type": "no route",
    "msg": {}
}
```

#### Exactly One Route Available

If the router knows exactly one possible route to the destination network, it should forward the data packet along the appropriate port.
Your router does not need to modify the data message in any way.

#### Multiple Routes Available

It is possible that your forwarding table will include multiple destination networks that all match the destination of the data packet.

If this is the case:

1. Choose the **longest prefix match** (longest netmask)
1. Choose the path with the highest *localpref*
1. Choose the path with *selfOrigin* = true
1. Choose the path with the shortest *ASPath*
1. Choose the path with the best *origin*, where IGP > EGP > UNK
1. The path from the neighbor router (i.e. the *src* of the update message) with the lowest IP address

#### Legally Forwarding

Assuming your router was able to find a path for the given data message, the final step before sending it to its destination is to ensure it is being forwarded legally.

- If the source router or destination router is a customer, then your router should forward the data
- If the source router is a peer or a provider, and the destination is a peer or a provider, then drop the data message

If your router drops a data message due to these restrictions, it should send a *no route* message back to the source.

### Dump and Table Messages

When your router receives a *dump* message, it must respond with a *table* message that contains a copy of the current forwarding table in your router.

Dump messages have the following format:

```json
{
    "src": "<source IP>",
    "dst": "<destination IP>",
    "type": "dump",
    "msg": {}
}
```

Table messages have the following format:

```json
{
    "src": "<source IP>",
    "dst": "<destination IP>",
    "type": "table",
    "msg":
    [
        {"network": "<network>", "netmask": "<cidr>", "peer": "<peer>"},
        {"network": "<network>", "netmask": "<cidr>", "peer": "<peer>"},
        ...
    ]
}
```

## Path Aggregation

An important function in real BGP routers is path aggregation: if there are two or more paths in the forwarding table that are:

1. Adjacent numerically
2. Forward to the same next-hop router
3. Have the same attributes (e.g. localpref, origin, etc.)

Then the two paths may be aggregated into a single path.

## Approach

Beginning this project was challenging.
Starting from the ground up, I created the polling functionality.
All testing was done inside the simulator.
Once I was able to successfully print all messages received, the parsing began.
Messages could be easily serialized into JSON objects, and then examined for their type.
Despite being readily-available objects, I created a hierarchy of message objects, which each perform specific functions and record specific information.
Based on the message type, the proper response could be taken.
The entirety of this functionality lays in the router object, and the forwarding tables encapsulated.
Finally, a few bit-wise operations were required to: convert the IP address between formats, calculate network changes upon updates or revokes, and ensure valid routing.

