from util import controller

class MyController(controller.Client):
    def arp_table_populate(self):
        print(f"[{self.sw}] - Populating the ARP Table")
        hosts = self.topo.get_hosts_connected_to(self.sw)

        #iterating over all hosts
        for host in hosts:
            ip_addr = self.topo.get_host_ip(host)
            mac_addr = self.topo.get_host_mac(host)

            # print(f"Host IP {ip_addr} with MAC {mac_addr} retrieved.")
            # self.table_add(table, action, keys, params) - adding values respectively , the keys and params should be arrays/lists
            self.table_add("ingress.arp_table", "ingress.arp_reply", [ip_addr], [mac_addr])
        
        print(f"[{self.sw}] - ARP Table Successfully Populated")
    
    def reset(self):
        print("Resetting....")
        super().reset()
        #extend the original reset with our arp_table appended
        self.table_reset("ingress.arp_table")

    
    def setup(self):
        super().setup()
        #trigger our added function
        self.arp_table_populate()

if __name__ == "__main__":
    c = controller.App(MyController())
