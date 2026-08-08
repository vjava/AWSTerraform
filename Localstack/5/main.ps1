<#
.SYNOPSIS
    Automated CloudFormation Orchestrator with Network ACL, VPC, and Compute for LocalStack
.DESCRIPTION
    Creates template.yaml automatically including NACL, Subnets, IGW, Route Tables, Security Groups, and EC2, then deploys it.
#>

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

function Write-PipelineLog {
    param (
        [Parameter(Mandatory=$true)][string]$Message,
        [ValidateSet("INFO", "SUCCESS", "WARNING", "ERROR")][string]$Level = "INFO"
    )
    $TimeStamp = (Get-Date).ToString("yyyy-MM-dd HH:mm:ss")
    $Color = switch ($Level) {
        "SUCCESS" { "Green" }
        "WARNING" { "Yellow" }
        "ERROR"   { "Red" }
        default   { "Cyan" }
    }
    Write-Host "[$TimeStamp] [$Level] $Message" -ForegroundColor $Color
}

Write-PipelineLog "Initializing CloudFormation Workflow with Network ACL..." "INFO"

$CfnFile = Join-Path $PSScriptRoot "template.yaml"
$EndpointUrl = "http://localhost:4566"
$StackName = "EnterpriseNetworkWithAclStack"

# ==============================================================================
# 1. CloudFormation YAML Template Generation (Including NACL)
# ==============================================================================
Write-PipelineLog "Generating template.yaml file with Network ACL and networking components..." "INFO"

$CloudFormationYaml = @'
AWSTemplateFormatVersion: '2010-09-09'
Description: Enterprise AWS Networking Stack with Network ACL on LocalStack

Resources:
  # 1. Virtual Private Cloud (VPC)
  MainVPC:
    Type: AWS::EC2::VPC
    Properties:
      CidrBlock: 10.200.0.0/16
      EnableDnsHostnames: true
      EnableDnsSupport: true
      Tags:
        - Key: Name
          Value: NACL-Test-MainVPC

  # 2. Internet Gateway
  InternetGateway:
    Type: AWS::EC2::InternetGateway
    Properties:
      Tags:
        - Key: Name
          Value: NACL-Test-IGW

  VPCGatewayAttachment:
    Type: AWS::EC2::VPCGatewayAttachment
    Properties:
      VpcId: !Ref MainVPC
      InternetGatewayId: !Ref InternetGateway

  # 3. Public Subnet 1 (AZ-1a)
  PublicSubnet1:
    Type: AWS::EC2::Subnet
    Properties:
      VpcId: !Ref MainVPC
      CidrBlock: 10.200.1.0/24
      AvailabilityZone: us-east-1a
      MapPublicIpOnLaunch: true
      Tags:
        - Key: Name
          Value: NACL-Test-PublicSubnet-AZ1

  # 4. Public Subnet 2 (AZ-1b)
  PublicSubnet2:
    Type: AWS::EC2::Subnet
    Properties:
      VpcId: !Ref MainVPC
      CidrBlock: 10.200.2.0/24
      AvailabilityZone: us-east-1b
      MapPublicIpOnLaunch: true
      Tags:
        - Key: Name
          Value: NACL-Test-PublicSubnet-AZ2

  # 5. Route Table & Association
  PublicRouteTable:
    Type: AWS::EC2::RouteTable
    Properties:
      VpcId: !Ref MainVPC
      Tags:
        - Key: Name
          Value: NACL-Test-PublicRouteTable

  DefaultPublicRoute:
    Type: AWS::EC2::Route
    DependsOn: VPCGatewayAttachment
    Properties:
      RouteTableId: !Ref PublicRouteTable
      DestinationCidrBlock: 0.0.0.0/0
      GatewayId: !Ref InternetGateway

  SubnetRouteTableAssociation1:
    Type: AWS::EC2::SubnetRouteTableAssociation
    Properties:
      SubnetId: !Ref PublicSubnet1
      RouteTableId: !Ref PublicRouteTable

  SubnetRouteTableAssociation2:
    Type: AWS::EC2::SubnetRouteTableAssociation
    Properties:
      SubnetId: !Ref PublicSubnet2
      RouteTableId: !Ref PublicRouteTable

  # 6. Network ACL (NACL)
  CustomNetworkAcl:
    Type: AWS::EC2::NetworkAcl
    Properties:
      VpcId: !Ref MainVPC
      Tags:
        - Key: Name
          Value: NACL-Test-CustomNACL

  # NACL Inbound Rule: Allow HTTP (Port 80)
  AclInboundHttp:
    Type: AWS::EC2::NetworkAclEntry
    Properties:
      NetworkAclId: !Ref CustomNetworkAcl
      RuleNumber: 100
      Protocol: 6 # TCP
      RuleAction: allow
      Egress: false
      CidrBlock: 0.0.0.0/0
      PortRange:
        From: 80
        To: 80

  # NACL Inbound Rule: Allow SSH (Port 22)
  AclInboundSsh:
    Type: AWS::EC2::NetworkAclEntry
    Properties:
      NetworkAclId: !Ref CustomNetworkAcl
      RuleNumber: 110
      Protocol: 6 # TCP
      RuleAction: allow
      Egress: false
      CidrBlock: 0.0.0.0/0
      PortRange:
        From: 22
        To: 22

  # NACL Inbound Rule: Allow Ephemeral Ports for Return Traffic
  AclInboundEphemeral:
    Type: AWS::EC2::NetworkAclEntry
    Properties:
      NetworkAclId: !Ref CustomNetworkAcl
      RuleNumber: 120
      Protocol: 6 # TCP
      RuleAction: allow
      Egress: false
      CidrBlock: 0.0.0.0/0
      PortRange:
        From: 1024
        To: 65535

  # NACL Outbound Rule: Allow All Traffic Out
  AclOutboundAll:
    Type: AWS::EC2::NetworkAclEntry
    Properties:
      NetworkAclId: !Ref CustomNetworkAcl
      RuleNumber: 100
      Protocol: -1 # All protocols
      RuleAction: allow
      Egress: true
      CidrBlock: 0.0.0.0/0

  # Associate NACL to Subnet 1
  SubnetAclAssociation1:
    Type: AWS::EC2::SubnetNetworkAclAssociation
    Properties:
      SubnetId: !Ref PublicSubnet1
      NetworkAclId: !Ref CustomNetworkAcl

  # Associate NACL to Subnet 2
  SubnetAclAssociation2:
    Type: AWS::EC2::SubnetNetworkAclAssociation
    Properties:
      SubnetId: !Ref PublicSubnet2
      NetworkAclId: !Ref CustomNetworkAcl

  # 7. Security Group
  WebSecurityGroup:
    Type: AWS::EC2::SecurityGroup
    Properties:
      GroupDescription: Allow HTTP and SSH traffic for NACL Testing
      VpcId: !Ref MainVPC
      SecurityGroupIngress:
        - IpProtocol: tcp
          FromPort: 80
          ToPort: 80
          CidrIp: 0.0.0.0/0
        - IpProtocol: tcp
          FromPort: 22
          ToPort: 22
          CidrIp: 0.0.0.0/0
      Tags:
        - Key: Name
          Value: NACL-Test-WebSG

  # 8. EC2 Instance 1
  WebServer1:
    Type: AWS::EC2::Instance
    Properties:
      ImageId: ami-12345678
      InstanceType: t2.micro
      SubnetId: !Ref PublicSubnet1
      SecurityGroupIds:
        - !Ref WebSecurityGroup
      Tags:
        - Key: Name
          Value: NACL-Test-WebServer-1

  # 9. EC2 Instance 2
  WebServer2:
    Type: AWS::EC2::Instance
    Properties:
      ImageId: ami-12345678
      InstanceType: t2.micro
      SubnetId: !Ref PublicSubnet2
      SecurityGroupIds:
        - !Ref WebSecurityGroup
      Tags:
        - Key: Name
          Value: NACL-Test-WebServer-2

Outputs:
  VpcId:
    Description: VPC ID
    Value: !Ref MainVPC
  NetworkAclId:
    Description: Network ACL ID
    Value: !Ref CustomNetworkAcl
  WebServer1Id:
    Description: EC2 Instance 1 ID
    Value: !Ref WebServer1
  WebServer2Id:
    Description: EC2 Instance 2 ID
    Value: !Ref WebServer2
'@

Set-Content -Path $CfnFile -Value $CloudFormationYaml -Encoding UTF8
Write-PipelineLog "template.yaml created with Network ACL successfully!" "SUCCESS"

# ==============================================================================
# 2. Execution & Stack Deployment via AWS CLI
# ==============================================================================
try {
    Write-PipelineLog "Deploying CloudFormation stack '$StackName' to LocalStack..." "INFO"

    aws --endpoint-url=$EndpointUrl cloudformation create-stack `
        --stack-name $StackName `
        --template-body "file://$CfnFile" `
        --region us-east-1 | Out-Null

    Write-PipelineLog "Waiting for CloudFormation stack creation to complete..." "INFO"
    aws --endpoint-url=$EndpointUrl cloudformation wait stack-create-complete --stack-name $StackName --region us-east-1

    Write-PipelineLog "CloudFormation Stack with Network ACL deployed successfully!" "SUCCESS"
    Write-PipelineLog "You can now verify the Network ACL and resources in the LocalStack Web UI under 'Network ACLs' and 'CloudFormation'." "SUCCESS"
}
catch {
    Write-PipelineLog "Pipeline Execution Error: $_" "ERROR"
}