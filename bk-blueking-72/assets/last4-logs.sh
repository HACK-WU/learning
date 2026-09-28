#!/usr/bin/env bash
NS=blueking

B_IAM=$(kubectl get pods -n $NS --no-headers 2>/dev/null | grep '^bkiam-saas-beat' | awk '{print $1}' | head -1)
W_IAM=$(kubectl get pods -n $NS --no-headers 2>/dev/null | grep '^bkiam-saas-worker' | awk '{print $1}' | head -1)
B_AGW=$(kubectl get pods -n $NS --no-headers 2>/dev/null | grep '^bk-apigateway-dashboard-beat' | awk '{print $1}' | head -1)
W_AGW=$(kubectl get pods -n $NS --no-headers 2>/dev/null | grep '^bk-apigateway-dashboard-celery' | awk '{print $1}' | head -1)

echo "=== Pod 名（精确） ==="
echo "    iam beat  = $B_IAM"
echo "    iam worker= $W_IAM"
echo "    agw beat  = $B_AGW"
echo "    agw worker= $W_AGW"

echo ""
echo "########## 1. bkiam-saas-beat ##########"
kubectl logs -n $NS $B_IAM --tail=20 2>&1 | sed 's/^/    /'

echo ""
echo "########## 2. bkiam-saas-worker ##########"
kubectl logs -n $NS $W_IAM --tail=25 2>&1 | sed 's/^/    /'

echo ""
echo "########## 3. apigateway-dashboard-beat ##########"
kubectl logs -n $NS $B_AGW --tail=20 2>&1 | sed 's/^/    /'

echo ""
echo "########## 4. apigateway-dashboard-celery ##########"
kubectl logs -n $NS $W_AGW --tail=25 2>&1 | sed 's/^/    /'
