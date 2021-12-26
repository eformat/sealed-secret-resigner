## sealed-secret-resigner

Resign all the sealed secrets in your cluster or project with a new master key.

Rotate master key, resign all sealed secrets in all namespaces with latest master:
```bash
 ./secret-resigner.sh
```

See `./secret-resigner.sh -h` for usage.
