#include <core.p4>
#include <v1model.p4>

// TODO: Extend and L2 switch with ARP resolution support

const bit<16> ETH_TYPE_ARP = 0x0806;
const bit<16> ARP_REQUEST = 1;
const bit<16> ARP_REPLY   = 2;
const bit<32> PKT_INSTANCE_TYPE_REPLICATION = 5;

header ethernet_t {
  bit<48> dstAddr;
  bit<48> srcAddr;
  bit<16> etherType;
}

// Defining the ARP Header here
header arp_t {
  bit<16> hType;
  bit<16> pType;
  bit<8> hLen;
  bit<8> pLen;
  bit<16> opcode;
  bit<48> sHwAddr;
  bit<32> sProcAddr;
  bit<48> tHwAddr;
  bit<32> tProcAddr;
}

struct headers_t {
  // TODO: Implement me
  ethernet_t ethernet;
  arp_t arp;
}

struct metadata_t { }

struct learn_t { bit<48> mac; bit<9>  ingress_port; }

parser parse(packet_in pkt, out headers_t hdr,
             inout metadata_t meta, inout standard_metadata_t std) {
  // TODO: Implement me
  state start {
    pkt.extract(hdr.ethernet);
    // applying a select on if ARP ethertype is detected - send to the arp-parser state if yes
    transition select(hdr.ethernet.etherType) {
      ETH_TYPE_ARP: arp_parser;
      default: accept;
    }
  }
  state arp_parser {
    //for arp_parser state, it passes and will be handled in ingress logic 
    pkt.extract(hdr.arp);
    transition accept;
  }
}

control ingress(inout headers_t hdr,
                inout metadata_t meta, inout standard_metadata_t std) {
  // extending the ingress logic from l2/switch_learning.p4 here
  action learn() { digest<learn_t>(1, { hdr.ethernet.srcAddr, std.ingress_port }); }
  table smac {
    key            = { hdr.ethernet.srcAddr : exact; }
    actions        = { learn; NoAction; }
    size           = 4096;
    default_action = learn();
  }

  register<bit<16>>(1) flood_mgid;

  action flood() { flood_mgid.read(std.mcast_grp, 0); }
  action forward(bit<9> port) { std.egress_spec = port; }
  table dmac {
    key            = { hdr.ethernet.dstAddr : exact; }
    actions        = { forward; flood; }
    size           = 4096;
    default_action = flood();
  }
  // ARP handling in ingress
  action arp_reply(bit<48> target_mac_addr) {
    hdr.arp.opcode = ARP_REPLY;

    //now we swap the mac addresses respectively
    hdr.arp.tHwAddr = hdr.arp.sHwAddr;
    hdr.arp.sHwAddr = target_mac_addr;
    //swapping the ip addresses
    bit<32> tmp_ip_holder = hdr.arp.tProcAddr;
    hdr.arp.tProcAddr = hdr.arp.sProcAddr;
    hdr.arp.sProcAddr = tmp_ip_holder;

    //for the ethernet header now
    hdr.ethernet.dstAddr = hdr.ethernet.srcAddr;
    hdr.ethernet.srcAddr = target_mac_addr;

    std.egress_spec = std.ingress_port;
  }
  table arp_table {
    key = { hdr.arp.tProcAddr: exact; }
    actions = { arp_reply; NoAction; }
    size = 1024;
    default_action = NoAction();
  }

  apply {
    // learning source mac from incoming packet
    if (hdr.ethernet.isValid()) {
      smac.apply();
    }

    //for arp requests apply the arp table otherwise, the normal dmac table applies
    if (hdr.arp.isValid() && hdr.arp.opcode == ARP_REQUEST) {
      arp_table.apply();
    } else {
      dmac.apply();
    }
  }
}

control egress(inout headers_t hdr,
               inout metadata_t meta, inout standard_metadata_t std) {
  // TODO: Implement me
    apply {
    if (std.instance_type == PKT_INSTANCE_TYPE_REPLICATION &&
        std.egress_port == std.ingress_port) {
      mark_to_drop(std);
    }
  }
}

control deparse(packet_out pkt, in headers_t hdr) {
  // TODO: Implement me
    apply {
    // A header is emitted only if it is "valid"
    pkt.emit(hdr.ethernet);
    pkt.emit(hdr.arp);
  }
}

control no_checksum(inout headers_t hdr, inout metadata_t meta) { apply {  } }

V1Switch(parse(),no_checksum(),ingress(),egress(),no_checksum(),deparse()) main;
