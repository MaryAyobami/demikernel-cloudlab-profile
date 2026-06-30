#!/usr/bin/env python
"""Demikernel reproduction profile 
"""

import geni.portal as portal
import geni.rspec.pg as pg

pc = portal.Context()

# Node types with Mellanox ConnectX-4 or newer NICs (required for Demikernel's DPDK/mlx5 backend).

NODE_TYPES = [
    ("d6515", "Utah d6515 (AMD EPYC, ConnectX-5 25GbE)"),
    ("xl170", "Utah xl170 (Intel Broadwell, ConnectX-4 10/25GbE)"),
    ("c6525-25g", "Utah c6525-25g (AMD EPYC, ConnectX-5 25GbE)"),
    ("c6525-100g", "Utah c6525-100g (AMD EPYC, ConnectX-5 100GbE)"),
    ("r7525", "Clemson r7525 (AMD EPYC, ConnectX-5/6, up to 100GbE)"),
]

OS_IMAGES = [
    ("urn:publicid:IDN+emulab.net+image+emulab-ops//UBUNTU20-64-STD",
     "Ubuntu 20.04"),
]

pc.defineParameter(
    "nodeType", "Physical Node Type",
    portal.ParameterType.STRING, NODE_TYPES[0][0], NODE_TYPES,
    longDescription="Node Type.")

pc.defineParameter(
    "nodeCount", "Number of Nodes",
    portal.ParameterType.INTEGER, 2,
    longDescription="Demikernel needs at least 2 nodes on the same LAN: "
                     "node0 (server) and node1 (client).")

pc.defineParameter(
    "osImage", "OS Image",
    portal.ParameterType.IMAGE, OS_IMAGES[0][0], OS_IMAGES,
    longDescription="Disk Image.")

params = pc.bindParameters()

if params.nodeCount < 2:
    pc.reportError(portal.ParameterError(
        "Demikernel requires at least 2 nodes.",
        ["nodeCount"]))

pc.verifyParameters()

request = pc.makeRequestRSpec()

lan = request.LAN("lan")

for i in range(params.nodeCount):
    node = request.RawPC("node%d" % i)
    node.hardware_type = params.nodeType
    node.disk_image = params.osImage

    iface = node.addInterface("if%d" % i)
    iface.addAddress(pg.IPv4Address("10.10.1.%d" % (i + 1), "255.255.255.0"))
    lan.addInterface(iface)

    # Run the setup script 
    node.addService(pg.Execute(
        shell="bash",
        command="sudo bash /local/repository/setup-demikernel-cloudlab.sh"))

pc.printRequestRSpec(request)
