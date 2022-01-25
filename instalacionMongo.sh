#!/bin/bash
set -e
logger "Arrancando instalacion y configuracion de MongoDB"
USO="Uso : install.sh [opciones]
Ejemplo:
install.sh -u administrador -p password [-n 27017]
Opciones:
-f archivo de configuración
-u usuario
-p password
-n numero de puerto (opcional)
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
while getopts ":u:p:n:f:a" OPCION
do
    case ${OPCION} in
        u ) USUARIO=$OPTARG
           echo "Parametro USUARIO establecido con '${USUARIO}'";;
        p ) PASSWORD=$OPTARG
           echo "Parametro PASSWORD establecido";;
        n ) PUERTO_MONGOD=$OPTARG
           echo "Parametro PUERTO_MONGOD establecido con '${PUERTO_MONGOD}'";;
        f ) ARCHIVO=$OPTARG
           echo "PARAMETRO DE ARCHIVO EXTABLECIDO CON '${ARCHIVO}'";;
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
            USUARIO=$user
            PASSWORD=$password
            PUERTO_MONGOD=$port 
        else
            echo "el archivo de configuración no tiene el formato correcto"
        fi
    else
        echo "el archivo de configuración es incorrecto"
    fi
fi

if [ -z ${USUARIO} ]
    then
        ayuda "El usuario (-u) debe ser especificado"; exit 1
fi
if [ -z ${PASSWORD} ]
    then
        echo "deb [ arch=amd64,arm64 ] https://repo.mongodb.org/apt/ubuntu xenial/mongodb-org/4.2 multiverse" | tee /etc/apt/sources.list.d/mongodb.list
fi
if [ -z ${PUERTO_MONGOD} ] 
    then
        PUERTO_MONGOD=27017
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
    port: ${PUERTO_MONGOD}
security:
    authorization: enabled
MONGOD_CONF
) > /etc/mongod.conf
# Reiniciar el servicio de mongod para aplicar la nueva configuracion
systemctl restart mongod 
# &&
i=0
while [[ $i -le 10 ]] ; do
    if nc -z localhost $PUERTO_MONGOD && [[ $(systemctl is-active mongod) == "active" ]];
    then
        break
    fi
    sleep 1
    ((i=i+1))
done

logger "Esperando a que mongod responda..."

#Si el servicio no está corriendo
mongo admin << CREACION_DE_USUARIO
db.createUser(
    {
        user: "${USUARIO}",
        pwd: "${PASSWORD}",
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

logger "El usuario ${USUARIO} ha sido creado con exito!"

exit 0