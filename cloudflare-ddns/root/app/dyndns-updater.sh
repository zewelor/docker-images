#!/bin/sh
set -e

DRY_RUN=$DRY_RUN

# Taken from: https://github.com/oznu/docker-cloudflare-ddns/blob/master/root/app/cloudflare.sh#L39
getPublicIpAddress() {
  # Use DNS_SERVER ENV variable or default to 1.1.1.1
  DNS_SERVER=${DNS_SERVER:=1.1.1.1}

  # try dns method first.
  CLOUD_FLARE_IP=$(dig +short @$DNS_SERVER ch txt whoami.cloudflare +time=3 | tr -d '"')
  CLOUD_FLARE_IP_LEN=${#CLOUD_FLARE_IP}

  # if using cloud flare fails, try opendns (some ISPs block 1.1.1.1)
  IP_ADDRESS=$([ $CLOUD_FLARE_IP_LEN -gt 15 ] && echo $(dig +short myip.opendns.com @resolver1.opendns.com +time=3) || echo "$CLOUD_FLARE_IP")

  # if dns method fails, use http method
  if [ "$IP_ADDRESS" = "" ]; then
    IP_ADDRESS=$(curl -sf4 https://ipconfig.io)
  fi

  if [ "$IP_ADDRESS" = "" ]; then
    IP_ADDRESS=$(curl --fail --silent --show-error ifconfig.co)
  fi

  echo $IP_ADDRESS
}

IP4NEW=`getPublicIpAddress`
echo "new IP:" $IP4NEW

dns_record_info=$(curl --fail --silent --show-error -X GET "https://api.cloudflare.com/client/v4/zones/$ZONE_ID/dns_records/$RECORD_ID" -H "Authorization: Bearer $API_TOKEN" -H "Content-Type: application/json")
echo "dns_record_info:" $dns_record_info
success=$(echo $dns_record_info | grep -o '"success":[^,]*' |  cut -d':' -f2)
if [[ $success != "true" ]]; then
  echo "Failed to read CF data:" $dns_record_info
  exit 1
else
  echo "DNS Record in CF found"
fi

IP4CUR=$(echo $dns_record_info | grep -o '"content":"[^"]*' | cut -d'"' -f4)
echo "IP in CF DNS Record:" $IP4CUR

if [ $IP4CUR == $IP4NEW ]; then
  echo "==> No changes needed! DNS Record currently is set to $IP4CUR"

  if [[ -n ${HC_URL} ]]; then
    echo "==> Pinging healthcheck: $HC_URL"
    curl -fsS -k -m 10 --retry 5 -o /dev/null $HC_URL
  fi
  
  exit
else
  echo "==> DNS Record currently is set to $IP4CUR". Updating!!!
fi

if [ -z $DRY_RUN ]; then
  ##### updates the dns record
  update=$(curl --fail --silent --show-error -X PUT "https://api.cloudflare.com/client/v4/zones/$ZONE_ID/dns_records/$RECORD_ID" \
      -H "Authorization: Bearer $API_TOKEN" \
      -H "Content-Type: application/json" \
      --data "{\"type\":\"A\",\"name\":\"$NAME\",\"content\":\"$IP4NEW\"}")

  if [[ $update == *"\"success\":false"* ]]; then
    echo -e "==> FAILED:\n$update"
    exit 1
  else
    echo "==> $dns_record DNS Record Updated To: $IP4NEW"
  fi

  if [[ -n ${HC_URL} ]]; then
    echo "==> Pinging healthcheck: $HC_URL"
    curl -fsS -k -m 10 --retry 5 -o /dev/null $HC_URL || true
  fi
else
  echo "==> Dry run, skipping update"
fi
