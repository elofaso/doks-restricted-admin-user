# doks-restricted-admin-user
Sample files for creating a user name 'joe' with restricted admin privileges limited to:
```
  Resources               Non-Resource URLs  Resource Names  Verbs
  ---------               -----------------  --------------  -----
  pods/log                []                 []              [get list]
  deployments.apps/scale  []                 []              [get update]
  pods                    []                 []              [list delete]
```

Directions:
1. Search & replace 'joe' with correct username in joe-restricted-admin-rolebinding.yaml.
2. `./addkubeuser.sh <username> <namespace> <cluster-name>`
3. `apply -f *.yaml`
4. Distribute generated kubeconfig file to user.
