# ===================================================================
# PASO PREVIO: Obtener el VPC ID por defecto
# ===================================================================

# Obtener el VPC ID por defecto de tu región
aws ec2 describe-vpcs \
  --filters "Name=isDefault,Values=true" \
  --query 'Vpcs[0].VpcId' \
  --output text

# O listar todas las VPCs disponibles
aws ec2 describe-vpcs \
  --query 'Vpcs[].[VpcId,IsDefault,Tags[?Key==`Name`].Value|[0]]' \
  --output table

# Guardar el VPC ID en una variable (Linux/Mac)
VPC_ID=$(aws ec2 describe-vpcs \
  --filters "Name=isDefault,Values=true" \
  --query 'Vpcs[0].VpcId' \
  --output text)

echo "VPC ID: $VPC_ID"

# ===================================================================
# VERIFICAR VERSIONES DISPONIBLES DE MYSQL
# ===================================================================

# Listar todas las versiones de MySQL disponibles en tu región
aws rds describe-db-engine-versions \
  --engine mysql \
  --query 'DBEngineVersions[*].[EngineVersion]' \
  --output table

# Ver solo las versiones más recientes
aws rds describe-db-engine-versions \
  --engine mysql \
  --query 'DBEngineVersions[?Status==`available`].[EngineVersion]' \
  --output table | tail -20

# Verificar versiones compatibles con db.t3.micro
aws rds describe-orderable-db-instance-options \
  --engine mysql \
  --db-instance-class db.t3.micro \
  --query 'OrderableDBInstanceOptions[*].[EngineVersion]' \
  --output table | sort -u

# ===================================================================
# COMANDOS AWS CLI PARA DESPLEGAR RDS CON CLOUDFORMATION
# ===================================================================

# 1. Validar la plantilla CloudFormation
aws cloudformation validate-template \
  --template-body file://rds-postgresql.yml

# 2. Crear el stack (OPCIÓN BÁSICA)
aws cloudformation create-stack \
  --stack-name webapp-rds-stack \
  --template-body file://rds-postgresql.yml \
  --parameters \
    ParameterKey=VpcId,ParameterValue=$VPC_ID \
    ParameterKey=AvailabilityZone,ParameterValue=eu-west-1a \
    ParameterKey=EnvironmentType,ParameterValue=dev \
    ParameterKey=KeyPairName,ParameterValue=tu-keypair \
    ParameterKey=DBPassword,ParameterValue=TuPassword123

# 3. Crear el stack (OPCIÓN CON TODOS LOS PARÁMETROS)
aws cloudformation create-stack \
  --stack-name webapp-rds-stack \
  --template-body file://rds-postgresql.yml \
  --parameters \
    ParameterKey=VpcId,ParameterValue=$VPC_ID \
    ParameterKey=AvailabilityZone,ParameterValue=eu-west-1a \
    ParameterKey=EnvironmentType,ParameterValue=dev \
    ParameterKey=KeyPairName,ParameterValue=vockey \
    ParameterKey=DBUsername,ParameterValue=mysqladmin \
    ParameterKey=DBPassword,ParameterValue=TuPassword123 \
    ParameterKey=DBName,ParameterValue=webapp

# 4. Monitorizar el estado de creación del stack
aws cloudformation describe-stacks \
  --stack-name webapp-rds-stack \
  --query 'Stacks[0].StackStatus'

# 5. Ver los eventos del stack en tiempo real
aws cloudformation describe-stack-events \
  --stack-name webapp-rds-stack \
  --max-items 10

# 6. Esperar a que el stack se complete (bloqueante)
aws cloudformation wait stack-create-complete \
  --stack-name webapp-rds-stack

# 7. Obtener los outputs del stack
aws cloudformation describe-stacks \
  --stack-name webapp-rds-stack \
  --query 'Stacks[0].Outputs'

# 8. Obtener solo el endpoint de la base de datos
aws cloudformation describe-stacks \
  --stack-name webapp-rds-stack \
  --query 'Stacks[0].Outputs[?OutputKey==`WebAppDatabaseEndpoint`].OutputValue' \
  --output text

# 9. Listar todos los recursos del stack
aws cloudformation list-stack-resources \
  --stack-name webapp-rds-stack

# 10. Actualizar el stack (si modificas la plantilla)
aws cloudformation update-stack \
  --stack-name webapp-rds-stack \
  --template-body file://rds-postgresql.yml \
  --parameters \
    ParameterKey=VpcId,ParameterValue=$VPC_ID \
    ParameterKey=AvailabilityZone,ParameterValue=eu-west-1a \
    ParameterKey=EnvironmentType,ParameterValue=dev \
    ParameterKey=KeyPairName,ParameterValue=tu-keypair \
    ParameterKey=DBPassword,ParameterValue=TuPassword123

# 11. Eliminar el stack
aws cloudformation delete-stack \
  --stack-name webapp-rds-stack

# 12. Esperar a que se complete la eliminación
aws cloudformation wait stack-delete-complete \
  --stack-name webapp-rds-stack

# ===================================================================
# COMANDOS ADICIONALES ÚTILES
# ===================================================================

# Listar todos los stacks
aws cloudformation list-stacks \
  --stack-status-filter CREATE_COMPLETE UPDATE_COMPLETE

# Ver detalles del stack en formato tabla
aws cloudformation describe-stacks \
  --stack-name webapp-rds-stack \
  --output table

# Obtener información de la instancia RDS creada
aws rds describe-db-instances \
  --db-instance-identifier webapp-db

# Conectar a la base de datos (desde EC2 o local con acceso)
# Primero obtén el endpoint:
DB_ENDPOINT=$(aws cloudformation describe-stacks \
  --stack-name webapp-rds-stack \
  --query 'Stacks[0].Outputs[?OutputKey==`WebAppDatabaseEndpoint`].OutputValue' \
  --output text)

# Luego conéctate:
psql -h $DB_ENDPOINT -U postgresadmin -d webapp

# ===================================================================
# USANDO ARCHIVO DE PARÁMETROS (RECOMENDADO PARA PRODUCCIÓN)
# ===================================================================

# Crear archivo parameters.json
cat > parameters.json << 'EOF'
[
  {
    "ParameterKey": "VpcId",
    "ParameterValue": "vpc-xxxxxxxx"
  },
  {
    "ParameterKey": "AvailabilityZone",
    "ParameterValue": "eu-west-1a"
  },
  {
    "ParameterKey": "EnvironmentType",
    "ParameterValue": "dev"
  },
  {
    "ParameterKey": "KeyPairName",
    "ParameterValue": "tu-keypair"
  },
  {
    "ParameterKey": "DBPassword",
    "ParameterValue": "TuPassword123"
  }
]
EOF

# Crear stack usando archivo de parámetros
aws cloudformation create-stack \
  --stack-name webapp-rds-stack \
  --template-body file://rds-postgresql.yml \
  --parameters file://parameters.json

# ===================================================================
# VERIFICAR LA CONFIGURACIÓN DE SEGURIDAD ENCADENADA
# ===================================================================

# Ver las reglas de entrada del Security Group de la EC2
aws ec2 describe-security-groups \
  --group-ids $(aws cloudformation describe-stack-resource \
    --stack-name webapp-rds-stack \
    --logical-resource-id WebAppSecurityGroup \
    --query 'StackResourceDetail.PhysicalResourceId' \
    --output text) \
  --query 'SecurityGroups[0].IpPermissions'

# Ver las reglas de entrada del Security Group de la base de datos
aws ec2 describe-security-groups \
  --group-ids $(aws cloudformation describe-stack-resource \
    --stack-name webapp-rds-stack \
    --logical-resource-id DatabaseSecurityGroup \
    --query 'StackResourceDetail.PhysicalResourceId' \
    --output text) \
  --query 'SecurityGroups[0].IpPermissions'

# Verificar que la base de datos NO es públicamente accesible
aws rds describe-db-instances \
  --db-instance-identifier webapp-db \
  --query 'DBInstances[0].PubliclyAccessible'

# ===================================================================
# CONECTARSE A LA BASE DE DATOS DESDE LA EC2
# ===================================================================

# 1. SSH a la instancia EC2
ssh -i tu-keypair.pem ec2-user@$(aws cloudformation describe-stacks \
  --stack-name webapp-rds-stack \
  --query 'Stacks[0].Outputs[?OutputKey==`WebServerPublicIP`].OutputValue' \
  --output text)

# 2. Dentro de la EC2, instalar cliente MySQL
sudo yum install -y mysql

# 3. Obtener el endpoint de la base de datos
DB_ENDPOINT=$(aws cloudformation describe-stacks \
  --stack-name webapp-rds-stack \
  --query 'Stacks[0].Outputs[?OutputKey==`WebAppDatabaseEndpoint`].OutputValue' \
  --output text)

# 4. Conectarse a la base de datos (solo funciona desde la EC2)
mysql -h $DB_ENDPOINT -u mysqladmin -p webapp

# ===================================================================
# DIAGRAMA DE ARQUITECTURA DE SEGURIDAD
# ===================================================================
#
#  Internet
#     |
#     | HTTP/HTTPS/SSH (0.0.0.0/0)
#     v
# ┌─────────────────────────┐
# │   WebAppSecurityGroup   │ <-- EC2 Instance
# │   (webapp-sg)           │
# └─────────────────────────┘
#     |
#     | MySQL 3306 (SOLO desde WebAppSG)
#     v
# ┌─────────────────────────┐
# │  DatabaseSecurityGroup  │ <-- RDS Instance
# │  (database-sg)          │     (NO público)
# └─────────────────────────┘
#
# VENTAJAS:
# - La base de datos NO es accesible desde Internet
# - Solo las instancias EC2 con el SG correcto pueden conectarse
# - Capa adicional de seguridad mediante encadenamiento de SGs
# - Tráfico encriptado en tránsito (StorageEncrypted: true)
#

# ===================================================================
# NOTAS IMPORTANTES
# ===================================================================
# - Reemplaza 'tu-keypair' con el nombre de tu Key Pair existente en AWS
# - Reemplaza 'TuPassword123' con una contraseña segura
# - Ajusta la zona de disponibilidad según tu región
# - El stack tarda aproximadamente 5-10 minutos en crear la instancia RDS
# - Asegúrate de tener los permisos necesarios en IAM
# - La base de datos SOLO es accesible desde la instancia EC2
# - NO podrás conectarte directamente desde tu máquina local a la BD
# - Usuario por defecto: mysqladmin
# - Motor: MySQL (puerto 3306)