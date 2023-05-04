# Troubleshooting

## 1. I can't connect over RPC

Try connecting directly to the container and running the following command:

```bash
curl --user litecoinrpc:xxxxxxxxxxxxxxx --data-binary '{"jsonrpc":"1.0","id":"curltext","method":"getblockchaininfo","params":[]}' -H 'content-type:text/plain;' http://127.0.0.1:9332
```

## 2. Daemon requires a reindex

If you see this error in the logs:

```
litecoind: Error: Please use -reindex or -reindex-chainstate to recover.
```

Then you need to reindex the blockchain. To do this, stop the container, and then run it again with the `CMD_OPTS=-reindex-chainstate` environment variable set:

```bash
docker run -d --name litecoin-node -v /data/litecoin:/home/litecoin/.litecoin -p 9332:9332 -p 9333:9333 --restart always -e "CMD_OPTS=-reindex-chainstate" ghcr.io/xorde-labs/docker-litecoin-node:latest
```

Or if you're using docker-compose, set the `CMD_OPTS` environment variable in your `.env` file:

```dotenv
CMD_OPTS=-reindex-chainstate
```

If the steps above don't work, you may need to do full reindex:

```bash
docker run -d --name litecoin-node -v /data/litecoin:/home/litecoin/.litecoin -p 9332:9332 -p 9333:9333 --restart always -e "CMD_OPTS=-reindex" ghcr.io/xorde-labs/docker-litecoin-node:latest
```

Or if you're using docker-compose, set the `CMD_OPTS` environment variable in your `.env` file:

```dotenv
CMD_OPTS=-reindex
```