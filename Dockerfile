FROM python:3.12-slim-bookworm

# runtime dependencies
# Run as uid:gid 999:999 to avoid conferring default UID 1000 permissions to key material
RUN set -eux; \
	groupadd -g 999 satosa; \
	useradd -m -g 999 -u 999 satosa; \
	apt-get update; \
	apt-get install -y --no-install-recommends \
		jq \
		libxml2-utils \
		xmlsec1 \
		git \
		patch \
	; \
	rm -rf /var/lib/apt/lists/*; \
	pip install --no-cache-dir \
		yq \
	;


# Install SATOSA from git latest since the latest release 8.4.0 lacks idpy_oidc_backend which is required for PKCE
# Also install ES256 compatible idpyoidc from fork while not fixed upstream: https://github.com/IdentityPython/idpy-oidc/issues/110
RUN set -eux; \
	pip install --no-cache-dir \
		'satosa[idpy_oidc_backend] @ git+https://github.com/IdentityPython/SATOSA' \
		'idpyoidc @ git+https://github.com/jinnatar/idpy-oidc@sign-algo-verify' \
	; \
	mkdir /etc/satosa; \
	chown -R satosa:satosa /etc/satosa

WORKDIR /etc/satosa

# Preload bespoke ENV configurable config
COPY *.yaml /etc/satosa

ENTRYPOINT ["gunicorn"]
EXPOSE 80
USER satosa:satosa
CMD ["-b0.0.0.0:80","satosa.wsgi:app"]
