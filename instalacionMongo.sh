#!/bin/bash
set -e
logger "Arrancando instalacion y configuracion de MongoDB"
USO="Uso : install.sh [opciones]
Ejemplo:
instalacionMongo.sh --f config.ini
Opciones:
-f archivo de configuración (user, password, port (opcional))
-a muestra esta ayuda
"

function ayuda() {
        echo "${USO}"
        if [[ ${1} ]]
    then
        echo ${1}
        fi
}
# Gestionar los argumentos
while getopts "f:a" OPCION
do
    case ${OPCION} in
        f ) ARCHIVO=$OPTARG
           echo "PARAMETRO DE ARCHIVO ESTABLECIDO CON '${ARCHIVO}'";;
        a ) ayuda; exit 0;;
        : ) ayuda "Falta el parametro para -$OPTARG"; exit 1;; \?) ayuda "La opcion no existe : $OPTARG"; exit 1;;
    esac
done

#Comprobar las variables del archivo de configuración
if [[ ! -z ${ARCHIVO} ]]; then
    if [[ -f ${ARCHIVO} ]]; then
        extension="${ARCHIVO##*.}"
        if [[ ${extension} == "ini" ]]; then
            source $ARCHIVO
        else
            echo "el archivo de configuración no tiene el formato correcto"
        fi
    else
        echo "el archivo de configuración es incorrecto"
    fi
fi

if [ -z ${user} ]
    then
        ayuda "El usuario (user / -u) debe ser especificado"; exit 1
fi
if [ -z ${password} ]
    then
        echo "deb [ arch=amd64,arm64 ] https://repo.mongodb.org/apt/ubuntu xenial/mongodb-org/4.2 multiverse" | tee /etc/apt/sources.list.d/mongodb.list
fi
if [ -z ${port} ] 
    then
        port=27017
fi

# Preparar el repositorio (apt-get) de mongodb añadir su clave apt
apt-key adv --keyserver hkp://keyserver.ubuntu.com:80 --recv 4B7C549A058F8B6B

echo "deb [ arch=amd64,arm64 ] https://repo.mongodb.org/apt/ubuntu xenial/mongodb-org/4.2 multiverse" | tee /etc/apt/sources.list.d/mongodb.list

if [[ -z "$(mongo --version 2> /dev/null | grep '4.2.1')" ]]
    then
        apt-get -y update \
        && apt-get install -y \
            mongodb-org=4.2.1 \
            mongodb-org-server=4.2.1 \
            mongodb-org-shell=4.2.1 \
            mongodb-org-mongos=4.2.1 \
            mongodb-org-tools=4.2.1 \
        && rm -rf /var/lib/apt/lists/* \
        && pkill -u mongodb || true \
        && pkill -f mongod || true \
        && rm -rf /var/lib/mongodb
fi
# Crear las carpetas de logs y datos con sus permisos
[[ -d "/datos/bd" ]] || mkdir -p -m 755 "/datos/bd"
[[ -d "/datos/log" ]] || mkdir -p -m 755 "/datos/log"
# Establecer el dueño y el grupo de las carpetas db y log
chown mongodb /datos/log /datos/bd
chgrp mongodb /datos/log /datos/bd
# Crear el archivo de configuración de mongodb con el puerto solicitado
mv /etc/mongod.conf /etc/mongod.conf.orig
(
cat << MONGOD_CONF
# /etc/mongod.conf
systemLog:
    destination: file
    path: /datos/log/mongod.log
    logAppend: true
storage:
    dbPath: /datos/bd
    engine: wiredTiger
    journal:
        enabled: true
net:
    port: ${port}
security:
    authorization: disabled
MONGOD_CONF
) > /etc/mongod.conf
# Reiniciar el servicio de mongod para aplicar la nueva configuracion
systemctl restart mongod 

logger "Esperando a que mongod responda..."

# Esperando a que mongod se inicia (despues de 10 intentos, se da por fallido)
i=0
until [[ $(mongo admin --quiet --eval "db.serverStatus().ok" 2> /dev/null) -eq 1 && i -lt 10 ]]
do
    sleep 1; ((i=i+1))
done

if [[ $i -lt 10 ]]; then 
#Si el servicio no está corriendo
mongo admin << CREACION_DE_USUARIO
db.createUser(
    {
        user: "${user}",
        pwd: "${password}",
        roles:[
        {
            role: "root",
            db: "admin"
        },
        {
            role: "restore",
            db: "admin"
        }]
    }
)
CREACION_DE_USUARIO
    logger "El usuario ${user} ha sido creado con exito!"
else 
    logger "Ha surgido un error al iniciar el servicio de mongoDB. Compruebe el fichero de configuración"
    echo "Ha surgido un error al iniciar el servicio de mongoDB. Compruebe el fichero de configuración"
fi

exit 0