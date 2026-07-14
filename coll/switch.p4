#include <core.p4>
#include <v1model.p4>

const bit<16> ETH_TYPE_IPV4 = 0x0800;
const bit<8>  UDP_PROTOCOL = 17;
const bit<16> COLLECT_PORT = 55555;

//construct the entire UDP header -- ethernet header (14 bytes) + ip header (20 bytes) + udp header (8 bytes)

header ethernet_t {
  bit<48> dstAddr;
  bit<48> srcAddr;
  bit<16> etherType;
}

header ipv4_t {
  bit<4>  version;
  bit<4>  ihl;
  bit<8>  diffserv;
  bit<16> totalLen;
  bit<16> identification;
  bit<3>  flags;
  bit<13> fragOffset;
  bit<8>  ttl;
  bit<8>  protocol;
  bit<16> hdrChecksum;
  bit<32> srcAddr;
  bit<32> dstAddr;
}

header udp_t {
  bit<16> srcPort;
  bit<16> dstPort;
  bit<16> length;
  bit<16> checksum;
}

//this is the layer 5 header used for our collective implementation
header collect_t {
  bit<32> index;
  int<32> value;
}

//putting arranging the headers together in a struct
struct headers_t {
  ethernet_t eth;
  ipv4_t     ip;
  udp_t      udp;
  collect_t     collect;
}

struct metadata_t {
  bool is_collect;
}

//parser implemented to parse l2,l3,l4 and l5 headers specifcally and pass on
parser parse(packet_in pkt, out headers_t hdr,
             inout metadata_t meta, inout standard_metadata_t std) {
  state start {
    pkt.extract(hdr.eth);
    transition select(hdr.eth.etherType) {
      ETH_TYPE_IPV4: parse_ipv4;
      default: accept;
    }
  }
  state parse_ipv4 {
    pkt.extract(hdr.ip);
    transition select(hdr.ip.protocol) {
      UDP_PROTOCOL: parse_udp;
      default: accept;
    }
  }
  state parse_udp {
    pkt.extract(hdr.udp);
    transition select(hdr.udp.dstPort) {
      COLLECT_PORT: parse_collect;
      default: accept;
    }
  }
  state parse_collect {
    pkt.extract(hdr.collect);
    transition accept;
  }
}

control ingress(inout headers_t hdr, inout metadata_t meta,
                inout standard_metadata_t std) {


  // dmac logic exactly derived from l2 switch.p4 implementation - this ensures the switch performs normal switching as usual
  register<bit<16>>(1) flood_mgid;

  action flood() { flood_mgid.read(std.mcast_grp, 0); }
  action forward(bit<9> port) { std.egress_spec = port; }

  table dmac {
    key            = { hdr.eth.dstAddr : exact; }
    actions        = { forward; flood; }
    size           = 4096;
    default_action = flood();
  }
  

  // SIGNED shortcut implemented similar to the calculator
  #define SIGNED(bits,var) ((int<bits>)(bit<bits>)var)


//define registers as per pseudocode with some self-assumptions
  register<bit<32>>(1024) pool_reg;
  register<bit<32>>(1024) count_reg;
  register<bit<32>>(1) num_workers_reg;
  register<bit<32>>(1) slot_index_reg;

  apply {
    if (hdr.collect.isValid()) {
      meta.is_collect = true;

      bit<32> pool_val;
      bit<32> count_val;
      bit<32> n;
      bit<32> slot_index;
      
      //read the registers and store the existing values in the newly defined variables
      pool_reg.read(pool_val, (bit<32>)hdr.collect.index);
      count_reg.read(count_val, (bit<32>)hdr.collect.index);
      num_workers_reg.read(n, 0);
      slot_index_reg.read(slot_index, 0);

    //   if (count_val == 0) {
    //     slot_index_reg.write(0, hdr.collect.index);
    //     slot_index = hdr.collect.index;
    //   }

    //   if (hdr.collect.index != slot_index) {
    //     mark_to_drop(std);
    //   } else {

      bit<32> new_pool_val = (bit<32>)(SIGNED(32, pool_val) + hdr.collect.value);
      bit<32> new_count_val = count_val + 1;

      log_msg("coll: idx={} val={} n={} count {}->{} pool {}->{}", {hdr.collect.index, hdr.collect.value, n, count_val, new_count_val, pool_val, new_pool_val});

      if (new_count_val == n) {
        // last contribution for this slot: reply to everyone, reset the slot
        hdr.collect.value = SIGNED(32, new_pool_val);

        hdr.udp.checksum = 0;   // this is to bypass the checksum- stop dropping aggregated packet due to checksum issues
        
        pool_reg.write((bit<32>)hdr.collect.index, 0);
        count_reg.write((bit<32>)hdr.collect.index, 0);
        flood_mgid.read(std.mcast_grp, 0);
      } else {
        pool_reg.write((bit<32>)hdr.collect.index, new_pool_val);
        count_reg.write((bit<32>)hdr.collect.index, new_count_val);
        mark_to_drop(std);                // not complete yet, absorb it
      }
      
    } else {
      meta.is_collect = false;
      dmac.apply();
    }
  }
}

control egress(inout headers_t hdr, inout metadata_t meta,
               inout standard_metadata_t std) {
  const bit<32> PKT_INSTANCE_TYPE_REPLICATION = 5;
  apply {
    if (!meta.is_collect && std.instance_type == PKT_INSTANCE_TYPE_REPLICATION && std.egress_port == std.ingress_port) {
      mark_to_drop(std);
    }
  }
}

//emit specific types of packets
control deparse(packet_out pkt, in headers_t hdr) {
  apply {
    pkt.emit(hdr.eth);
    pkt.emit(hdr.ip);
    pkt.emit(hdr.udp);
    pkt.emit(hdr.collect);
  }
}

control no_checksum(inout headers_t hdr, inout metadata_t meta) { apply { } }

V1Switch(parse(), no_checksum(), ingress(), egress(), no_checksum(), deparse()) main;