ARG ALPINE_VERSION
FROM alpine:${ALPINE_VERSION}

ARG DEHYDRATED_COMMIT=91cccc0c234e4decf0a19595fa19a6f306788032 \
    CLOUDFLARE_HOOK_COMMIT=f115f938e5ad5b86e358ecbf9684b325397ef4c5

ENV HOOK_PATH=hooks/cloudflare_hook

RUN mkdir -p /dehydrated/hooks && \
    mkdir -p /usr/share/publicsuffix

ADD wrapper.sh /dehydrated/

WORKDIR /dehydrated

RUN apk add --update curl openssl bash mawk jq bind-tools && \
    wget https://raw.githubusercontent.com/dehydrated-io/dehydrated/$DEHYDRATED_COMMIT/dehydrated && \
    wget https://raw.githubusercontent.com/socram8888/dehydrated-hook-cloudflare/$CLOUDFLARE_HOOK_COMMIT/cf-hook.sh -O $HOOK_PATH && \
    wget https://publicsuffix.org/list/effective_tld_names.dat -O /usr/share/publicsuffix/effective_tld_names.dat && \  
    rm -rf /var/cache/apk/* /tmp/* /var/tmp/ && \
    chown nobody:nogroup -R /dehydrated && \
    chmod +x /dehydrated/dehydrated /dehydrated/$HOOK_PATH /dehydrated/wrapper.sh && \
    touch /dehydrated/domains.txt

USER nobody:nogroup

CMD /dehydrated/wrapper.sh

