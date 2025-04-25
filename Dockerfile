FROM python:3.12-alpine

ENV SATOSA_VERSION="8.5.1"

# While SATOSA now has a release with modern OIDC support, it's dependency idpyoidc has not yet
# made a release that allows ES256. Ergo, we pull that dep in from the branch that most
# closely matches where they usually cut releases from.
# More context: https://github.com/IdentityPython/idpy-oidc/issues/114
ENV IDPYOIDC_REF="git+https://github.com/IdentityPython/idpy-oidc@issuer_metadata"

# Run as uid:gid 999:999 to avoid conferring default UID 1000 permissions to key material
RUN set -eux; \
	delgroup ping ; \
	addgroup -g 999 satosa; \
	adduser -g 999 -Su 999 satosa; \
	apk update; \
	apk add --no-cache \
		jq \
		libxml2-utils \
		xmlsec \
    git
# ^ Only needed until we have a non-git idpyoidc ref


RUN pip install --no-cache-dir \
yq \
"satosa[idpy_oidc_backend]==${SATOSA_VERSION}" \
"idpyoidc @ ${IDPYOIDC_REF}"

RUN	mkdir /etc/satosa && chown -R satosa:satosa /etc/satosa
WORKDIR /etc/satosa

# Preload bespoke ENV configurable config
COPY *.yaml /etc/satosa
# Preload dummy XML metadata
COPY dummy-metadata.xml /etc/satosa

# Add an entrypoint so we can use ENV for gunicorn args
ENV LOG_LEVEL="INFO"
ENV LISTEN_ADDR="0.0.0.0:80"
COPY entrypoint.sh /entrypoint.sh
ENTRYPOINT ["/entrypoint.sh"]

EXPOSE 80
USER satosa:satosa
