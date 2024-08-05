1. Generate your SAML2 certs: `openssl req -x509 -sha256 -nodes -days 365 -newkey rsa:2048 -keyout saml.key -out saml.crt` .. Be sure to set the Common Name to your proxy domain, for example `saml.example.com`
1. Create your env variables starting from the examples: `cp example.env prod.env` .. and edit `prod.env`
1. Generate your metadata: `docker run --rm -it -v $PWD:/conf -w /conf --user $UID --env-file prod.env --entrypoint satosa-saml-metadata satosa:latest proxy_conf.yaml saml.key saml.crt`
