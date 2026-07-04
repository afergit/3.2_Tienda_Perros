#!/bin/bash
set -e

echo "Iniciando creación de la red de AWS para tienda-eks..."

# 1. Crear VPC (CIDR 10.0.0.0/16)
vpc_json=$(aws ec2 create-vpc --cidr-block 10.0.0.0/16 --no-cli-pager)
vpcId=$(echo "$vpc_json" | jq -r '.Vpc.VpcId')
echo "VPC Creada: $vpcId"

# Habilitar nombres de host DNS en la VPC (Obligatorio para EKS)
aws ec2 modify-vpc-attribute --vpc-id "$vpcId" --enable-dns-hostnames '{"Value":true}' --no-cli-pager
aws ec2 modify-vpc-attribute --vpc-id "$vpcId" --enable-dns-support '{"Value":true}' --no-cli-pager
echo "Soporte de DNS habilitado en la VPC."

# Taggear la VPC
aws ec2 create-tags --resources "$vpcId" --tags Key=Name,Value=tienda-vpc --no-cli-pager

# 2. Crear Internet Gateway (IGW) y adjuntarlo a la VPC
igw_json=$(aws ec2 create-internet-gateway --no-cli-pager)
igwId=$(echo "$igw_json" | jq -r '.InternetGateway.InternetGatewayId')
aws ec2 attach-internet-gateway --vpc-id "$vpcId" --internet-gateway-id "$igwId" --no-cli-pager
echo "Internet Gateway Creado ($igwId) y adjuntado a la VPC."
aws ec2 create-tags --resources "$igwId" --tags Key=Name,Value=tienda-igw --no-cli-pager

# 3. Crear Subredes Públicas (en zonas de disponibilidad diferentes para alta disponibilidad de EKS)
subnet1_json=$(aws ec2 create-subnet --vpc-id "$vpcId" --cidr-block 10.0.1.0/24 --availability-zone us-east-1a --no-cli-pager)
subnet1Id=$(echo "$subnet1_json" | jq -r '.Subnet.SubnetId')

subnet2_json=$(aws ec2 create-subnet --vpc-id "$vpcId" --cidr-block 10.0.2.0/24 --availability-zone us-east-1b --no-cli-pager)
subnet2Id=$(echo "$subnet2_json" | jq -r '.Subnet.SubnetId')

echo "Subred 1 (us-east-1a) Creada: $subnet1Id"
echo "Subred 2 (us-east-1b) Creada: $subnet2Id"

# Configurar subredes para asignar IPs públicas automáticamente a las instancias
aws ec2 modify-subnet-attribute --subnet-id "$subnet1Id" --map-public-ip-on-launch --no-cli-pager
aws ec2 modify-subnet-attribute --subnet-id "$subnet2Id" --map-public-ip-on-launch --no-cli-pager

# 4. Crear Tabla de Ruteo Pública y asociar la ruta al Internet Gateway
rtb_json=$(aws ec2 create-route-table --vpc-id "$vpcId" --no-cli-pager)
rtbId=$(echo "$rtb_json" | jq -r '.RouteTable.RouteTableId')
aws ec2 create-route --route-table-id "$rtbId" --destination-cidr-block 0.0.0.0/0 --gateway-id "$igwId" --no-cli-pager > /dev/null
echo "Tabla de Ruteo Creada ($rtbId) con ruta hacia el IGW (0.0.0.0/0)."
aws ec2 create-tags --resources "$rtbId" --tags Key=Name,Value=tienda-public-rt --no-cli-pager

# Asociar subredes a la Tabla de Ruteo
aws ec2 associate-route-table --subnet-id "$subnet1Id" --route-table-id "$rtbId" --no-cli-pager > /dev/null
aws ec2 associate-route-table --subnet-id "$subnet2Id" --route-table-id "$rtbId" --no-cli-pager > /dev/null
echo "Subredes asociadas a la tabla de ruteo pública."

# 5. Aplicar Etiquetas (Tags) requeridas por EKS y el Balanceador (ELB)
# Importante: EKS necesita saber qué subredes son públicas para colocar el balanceador externo.
aws ec2 create-tags --resources "$subnet1Id" "$subnet2Id" --tags Key=kubernetes.io/cluster/tienda-eks,Value=shared Key=kubernetes.io/role/elb,Value=1 --no-cli-pager
aws ec2 create-tags --resources "$subnet1Id" --tags Key=Name,Value=tienda-public-1a --no-cli-pager
aws ec2 create-tags --resources "$subnet2Id" --tags Key=Name,Value=tienda-public-1b --no-cli-pager
echo "Etiquetas requeridas por EKS y ELB aplicadas correctamente en las subredes."

echo -e "\n=== DETALLES DE TU RED AWS ==="
echo "ID de VPC: $vpcId"
echo "Subred 1:  $subnet1Id (us-east-1a)"
echo "Subred 2:  $subnet2Id (us-east-1b)"
echo "=============================="
echo "¡Red lista! Ya puedes usar esta VPC en la consola web para crear tu EKS."
