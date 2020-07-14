## Reference https://docs.microsoft.com/en-us/azure/firewall/tutorial-hybrid-ps
    # When you connect your on-premises network to an Azure virtual network to create a hybrid network, the ability to control access to your Azure network resources is an important part of an overall security plan.
    # You can use Azure Firewall to control network access in a hybrid network using rules that define allowed and denied network traffic.
    # In this script you create four virtual networks:
        # VNet-Hub - the firewall is in this virtual network.
        # VNet-Spoke - the spoke virtual network representing Prod or Dev workloads located on Azure.
        # VNet-Onprem - The on-premises virtual network represents an on-premises network. In an actual deployment, it can be connected by either a VPN or ExpressRoute connection. 
                        # For simplicity, this article uses a VPN gateway connection, and an Azure-located virtual network is used to represent an on-premises network.

            # In this script you will:

                # Declare the variables
                # Create the firewall hub virtual network
                # Create the spoke virtual networks
                # Create the on-premises virtual network
                # Configure and deploy the firewall
                # Create and connect the VPN gateways
                # Peer the hub and spoke virtual networks
                # Create the routes
                # Create the virtual machines
                # Test the firewall

## Declare Variables
    $RG1 = "demo-hybridnet-rg"
    $Location1 = "West Europe"

    # Variables for the firewall hub VNet

    $VNetnameHub = "VNet-hub"
    $SNnameHub = "AzureFirewallSubnet"
    $VNetHubPrefix = "10.5.0.0/16"
    $SNHubPrefix = "10.5.0.0/24"
    $SNGWHubPrefix = "10.5.1.0/24"
    $GWHubName = "GW-hub"
    $GWHubpipName = "VNet-hub-GW-pip"
    $GWIPconfNameHub = "GW-ipconf-hub"
    $ConnectionNameHub = "hub-to-Onprem"

    # Variables for the spoke virtual network

    $VnetNameSpoke = "VNet-Spoke"
    $SNnameSpoke = "SN-Workload"
    $VNetSpokePrefix = "10.6.0.0/16"
    $SNSpokePrefix = "10.6.0.0/24"
    $SNSpokeGWPrefix = "10.6.1.0/24"

    # Variables for the on-premises virtual network

    $VNetnameOnprem = "Vnet-Onprem"
    $SNNameOnprem = "SN-Corp"
    $VNetOnpremPrefix = "192.168.0.0/16"
    $SNOnpremPrefix = "192.168.1.0/24"
    $SNGWOnpremPrefix = "192.168.2.0/24"
    $GWOnpremName = "GW-Onprem"
    $GWIPconfNameOnprem = "GW-ipconf-Onprem"
    $ConnectionNameOnprem = "Onprem-to-hub"
    $GWOnprempipName = "VNet-Onprem-GW-pip"

    $SNnameGW = "GatewaySubnet"

## Create the firewall hub virtual network
   # First, create the resource group to contain the resources for this article:
   New-AzResourceGroup -Name $RG1 -Location $Location1
   
   # Define the subnets to be included in the virtual network:
    $FWsub = New-AzVirtualNetworkSubnetConfig -Name $SNnameHub -AddressPrefix $SNHubPrefix
    $GWsub = New-AzVirtualNetworkSubnetConfig -Name $SNnameGW -AddressPrefix $SNGWHubPrefix
    
        # Create the firewall hub virtual network:
        $VNetHub = New-AzVirtualNetwork -Name $VNetnameHub -ResourceGroupName $RG1 `
        -Location $Location1 -AddressPrefix $VNetHubPrefix -Subnet $FWsub,$GWsub
    
        # Request a public IP address to be allocated to the VPN gateway you'll create for your virtual network.
        $gwpip1 = New-AzPublicIpAddress -Name $GWHubpipName -ResourceGroupName $RG1 `
        -Location $Location1 -AllocationMethod Dynamic

## Create the spoke virtual network
    # Define the subnets to be included in the spoke virtual network:
    $Spokesub = New-AzVirtualNetworkSubnetConfig -Name $SNnameSpoke -AddressPrefix $SNSpokePrefix
    $GWsubSpoke = New-AzVirtualNetworkSubnetConfig -Name $SNnameGW -AddressPrefix $SNSpokeGWPrefix
        
        # Create the spoke virtual network        
        $VNetSpoke = New-AzVirtualNetwork -Name $VnetNameSpoke -ResourceGroupName $RG1 `
        -Location $Location1 -AddressPrefix $VNetSpokePrefix -Subnet $Spokesub,$GWsubSpoke

## Create the on-premises virtual network
    # Define the subnets to be included in the virtual network:
    $Onpremsub = New-AzVirtualNetworkSubnetConfig -Name $SNNameOnprem -AddressPrefix $SNOnpremPrefix
    $GWOnpremsub = New-AzVirtualNetworkSubnetConfig -Name $SNnameGW -AddressPrefix $SNGWOnpremPrefix
    
        # Create the on-premises virtual network
        $VNetOnprem = New-AzVirtualNetwork -Name $VNetnameOnprem -ResourceGroupName $RG1 `
        -Location $Location1 -AddressPrefix $VNetOnpremPrefix -Subnet $Onpremsub,$GWOnpremsub

            # Request a public IP address to be allocated to the gateway you'll create for the virtual network
            $gwOnprempip = New-AzPublicIpAddress -Name $GWOnprempipName -ResourceGroupName $RG1 `
            -Location $Location1 -AllocationMethod Dynamic

## Configure and deploy the firewall
    # Deploy the firewall into the hub virtual network.
        # Get a Public IP for the firewall
        $FWpip = New-AzPublicIpAddress -Name "fw-pip" -ResourceGroupName $RG1 `
        -Location $Location1 -AllocationMethod Static -Sku Standard
        
            # Create the firewall
            $Azfw = New-AzFirewall -Name AzFW01 -ResourceGroupName $RG1 -Location $Location1 -VirtualNetworkName $VNetnameHub -PublicIpName fw-pip
            
            #Save the firewall private IP address as a variable for future use
            $AzfwPrivateIP = $Azfw.IpConfigurations.privateipaddress
            $AzfwPrivateIP
            
                # Configure network rules
                $Rule1 = New-AzFirewallNetworkRule -Name "AllowWeb" -Protocol TCP -SourceAddress $SNOnpremPrefix `
                    -DestinationAddress $VNetSpokePrefix -DestinationPort 80

                $Rule2 = New-AzFirewallNetworkRule -Name "AllowRDP" -Protocol TCP -SourceAddress $SNOnpremPrefix `
                    -DestinationAddress $VNetSpokePrefix -DestinationPort 3389        
                
                $NetRuleCollection = New-AzFirewallNetworkRuleCollection -Name RCNet01 -Priority 100 `
                    -Rule $Rule1,$Rule2 -ActionType "Allow"
                
                $Azfw.NetworkRuleCollections = $NetRuleCollection
                Set-AzFirewall -AzureFirewall $Azfw

## Create and connect the VPN gateways
## Network-to-network configurations require a RouteBased VpnType. Creating a VPN gateway can often take 45 minutes or more, depending on the selected VPN gateway SKU
    # Create a VPN gateway for the hub virtual network
        # Create the VPN gateway configuration
        $vnet1 = Get-AzVirtualNetwork -Name $VNetnameHub -ResourceGroupName $RG1
        $subnet1 = Get-AzVirtualNetworkSubnetConfig -Name "GatewaySubnet" -VirtualNetwork $vnet1
        $gwipconf1 = New-AzVirtualNetworkGatewayIpConfig -Name $GWIPconfNameHub `
        -Subnet $subnet1 -PublicIpAddress $gwpip1

            # Create a VPN gateway for the hub virtual network
            New-AzVirtualNetworkGateway -Name $GWHubName -ResourceGroupName $RG1 `
            -Location $Location1 -IpConfigurations $gwipconf1 -GatewayType Vpn `
            -VpnType RouteBased -GatewaySku basic
        
    # Create a VPN gateway for the on-premises virtual network
        # Create the VPN gateway configuration
        $vnet2 = Get-AzVirtualNetwork -Name $VNetnameOnprem -ResourceGroupName $RG1
        $subnet2 = Get-AzVirtualNetworkSubnetConfig -Name "GatewaySubnet" -VirtualNetwork $vnet2
        $gwipconf2 = New-AzVirtualNetworkGatewayIpConfig -Name $GWIPconfNameOnprem `
        -Subnet $subnet2 -PublicIpAddress $gwOnprempip
                
            # Create the VPN gateway for the on-premises virtual network
            New-AzVirtualNetworkGateway -Name $GWOnpremName -ResourceGroupName $RG1 `
            -Location $Location1 -IpConfigurations $gwipconf2 -GatewayType Vpn `
            -VpnType RouteBased -GatewaySku basic

    # Create the VPN connections
        # Get the VPN gateways
        $vnetHubgw = Get-AzVirtualNetworkGateway -Name $GWHubName -ResourceGroupName $RG1
        $vnetOnpremgw = Get-AzVirtualNetworkGateway -Name $GWOnpremName -ResourceGroupName $RG1
        
        # Create the connections
        New-AzVirtualNetworkGatewayConnection -Name $ConnectionNameHub -ResourceGroupName $RG1 `
        -VirtualNetworkGateway1 $vnetHubgw -VirtualNetworkGateway2 $vnetOnpremgw -Location $Location1 `
        -ConnectionType Vnet2Vnet -SharedKey 'AzureA1b2C3'
            # Create the on-premises to hub virtual network connection
            New-AzVirtualNetworkGatewayConnection -Name $ConnectionNameOnprem -ResourceGroupName $RG1 `
                -VirtualNetworkGateway1 $vnetOnpremgw -VirtualNetworkGateway2 $vnetHubgw -Location $Location1 `
                -ConnectionType Vnet2Vnet -SharedKey 'AzureA1b2C3'
        
        # Verify the connection
        # You can verify a successful connection by using the Get-AzVirtualNetworkGatewayConnection cmdlet, with or without -Debug
        #Get-AzVirtualNetworkGatewayConnection -Name $ConnectionNameHub -ResourceGroupName $RG1

# Peer the hub and spoke virtual networks
    # Peer hub to spoke
    Add-AzVirtualNetworkPeering -Name HubtoSpoke -VirtualNetwork $VNetHub -RemoteVirtualNetworkId $VNetSpoke.Id -AllowGatewayTransit

    # Peer spoke to hub
    Add-AzVirtualNetworkPeering -Name SpoketoHub -VirtualNetwork $VNetSpoke -RemoteVirtualNetworkId $VNetHub.Id -AllowForwardedTraffic -UseRemoteGateways

# Create routes
    #Create a route table
    $routeTableHubSpoke = New-AzRouteTable `
    -Name 'UDR-Hub-Spoke' `
    -ResourceGroupName $RG1 `
    -location $Location1

    #Create a route
    Get-AzRouteTable `
    -ResourceGroupName $RG1 `
    -Name UDR-Hub-Spoke `
    | Add-AzRouteConfig `
    -Name "ToSpoke" `
    -AddressPrefix $VNetSpokePrefix `
    -NextHopType "VirtualAppliance" `
    -NextHopIpAddress $AzfwPrivateIP `
    | Set-AzRouteTable

    #Associate the route table to the subnet

    Set-AzVirtualNetworkSubnetConfig `
    -VirtualNetwork $VNetHub `
    -Name $SNnameGW `
    -AddressPrefix $SNGWHubPrefix `
    -RouteTable $routeTableHubSpoke | `
    Set-AzVirtualNetwork

    #Now create the default route

    #Create a table, with BGP route propagation (aka "Virtual network gateway route propagation") disabled
    $routeTableSpokeDG = New-AzRouteTable `
    -Name 'UDR-DG' `
    -ResourceGroupName $RG1 `
    -location $Location1 `
    -DisableBgpRoutePropagation

    #Create a route
    Get-AzRouteTable `
    -ResourceGroupName $RG1 `
    -Name UDR-DG `
    | Add-AzRouteConfig `
    -Name "ToFirewall" `
    -AddressPrefix 0.0.0.0/0 `
    -NextHopType "VirtualAppliance" `
    -NextHopIpAddress $AzfwPrivateIP `
    | Set-AzRouteTable

    #Associate the route table to the subnet

    Set-AzVirtualNetworkSubnetConfig `
    -VirtualNetwork $VNetSpoke `
    -Name $SNnameSpoke `
    -AddressPrefix $SNSpokePrefix `
    -RouteTable $routeTableSpokeDG | `
    Set-AzVirtualNetwork

# Create virtual machines
    # Create an inbound network security group rule for ports 3389 and 80
    $nsgRuleRDP = New-AzNetworkSecurityRuleConfig -Name Allow-RDP  -Protocol Tcp `
      -Direction Inbound -Priority 200 -SourceAddressPrefix * -SourcePortRange * -DestinationAddressPrefix $SNSpokePrefix -DestinationPortRange 3389 -Access Allow
    $nsgRuleWeb = New-AzNetworkSecurityRuleConfig -Name Allow-web  -Protocol Tcp `
      -Direction Inbound -Priority 202 -SourceAddressPrefix * -SourcePortRange * -DestinationAddressPrefix $SNSpokePrefix -DestinationPortRange 80 -Access Allow
    
    # Create a network security group
    $nsg = New-AzNetworkSecurityGroup -ResourceGroupName $RG1 -Location $Location1 -Name NSG-Spoke02 -SecurityRules $nsgRuleRDP,$nsgRuleWeb
    
    #Create the NIC
    $NIC = New-AzNetworkInterface -Name spoke-01 -ResourceGroupName $RG1 -Location $Location1 -SubnetId $VnetSpoke.Subnets[0].Id -NetworkSecurityGroupId $nsg.Id
    
    #Define the virtual machine
    $VirtualMachine = New-AzVMConfig -VMName VM-Spoke-01 -VMSize "Standard_B2s"
    $VirtualMachine = Set-AzVMOperatingSystem -VM $VirtualMachine -Windows -ComputerName Spoke-01 -ProvisionVMAgent -EnableAutoUpdate
    $VirtualMachine = Add-AzVMNetworkInterface -VM $VirtualMachine -Id $NIC.Id
    $VirtualMachine = Set-AzVMSourceImage -VM $VirtualMachine -PublisherName 'MicrosoftWindowsServer' -Offer 'WindowsServer' -Skus '2019-Datacenter' -Version latest
    
    #Create the virtual machine
    New-AzVM -ResourceGroupName $RG1 -Location $Location1 -VM $VirtualMachine -Verbose
    
    #Install IIS on the VM
    Set-AzVMExtension `
        -ResourceGroupName $RG1 `
        -ExtensionName IIS `
        -VMName VM-Spoke-01 `
        -Publisher Microsoft.Compute `
        -ExtensionType CustomScriptExtension `
        -TypeHandlerVersion 1.4 `
        -SettingString '{"commandToExecute":"powershell.exe Install-WindowsFeature -Name Web-Server -IncludeManagementTools; powershell.exe Add-Content -Path \"C:\\inetpub\\wwwroot\\Default.htm\" -Value $($env:computername)"}' `
        -Location $Location1
    
        # Create the on-premises virtual machine
        New-AzVm `
        -ResourceGroupName $RG1 `
        -Name "VM-Onprem" `
        -Location $Location1 `
        -VirtualNetworkName $VNetnameOnprem `
        -SubnetName $SNNameOnprem `
        -OpenPorts 3389 `
        -Size "Standard_B2s"