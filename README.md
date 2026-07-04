# Tienda de Perritos en Amazon EKS (Actividad 3.2.3)

Este proyecto consiste en el despliegue de una aplicación web de tres capas (**Base de datos MySQL**, **Backend API en Node.js** e **Interfaz Frontend en Nginx**) sobre un clúster de Kubernetes administrado por AWS (**Elastic Kubernetes Service - EKS**), integrando políticas de autoescalado automático (HPA) y tolerancia a fallos (Auto-Healing).

---

## 🛠️ Requisitos Previos
*   Cuenta de **AWS Academy** activa.
*   Herramientas locales instaladas: **AWS CLI**, **kubectl**, **Docker Desktop** y **Git**.

---

## 🚀 Guía de Despliegue Paso a Paso

### Paso 1: Configurar Credenciales de AWS Academy
Dado que las credenciales de AWS Academy son temporales, ejecuta estos comandos en tu terminal local (PowerShell o CMD) para iniciar sesión:

```powershell
aws configure set aws_access_key_id "TU_ACCESS_KEY"
aws configure set aws_secret_access_key "TU_SECRET_KEY"
aws configure set default.region "us-east-1"
aws configure set default.output "json"
aws configure set aws_session_token "TU_SESSION_TOKEN_LARGO"
```

#### 💡 Solución de Problemas (Comando "more" no reconocido)
Si al validar tus credenciales con `aws sts get-caller-identity` obtienes el error `"more" no se reconoce como un comando interno...`, desactiva el paginador de AWS ejecutando:
```powershell
$env:AWS_PAGER=""
# O de forma explícita en cada comando:
aws sts get-caller-identity --no-cli-pager
```

---

### Paso 2: Desplegar la Red de AWS (VPC y Subredes)
Es recomendable crear la red utilizando **Infraestructura como Código (IaC)**. Puedes hacerlo de dos formas:

*   **Opción A (GitOps - Recomendado):** Sube el código a GitHub, configura los secretos del repositorio (`AWS_ACCESS_KEY_ID`, `AWS_SECRET_ACCESS_KEY`, `AWS_SESSION_TOKEN`) y ejecuta el Workflow **Deploy Red AWS** desde la pestaña de **Actions**.
*   **Opción B (Local):** Ejecuta el script de PowerShell en tu PC. 
    *   *Nota:* Si tu ruta tiene espacios (ej: `DUOC UC`), encierra la ruta en comillas:
    ```powershell
    & ".\3.2.3 APP tienda-perritos-EKS_MANUAL\scripts\crear-red-lab.ps1"
    ```

El script creará una VPC con **dos subredes públicas** en zonas de disponibilidad diferentes (`us-east-1a` y `us-east-1b`) y les aplicará las etiquetas necesarias para que EKS las reconozca automáticamente:
*   `kubernetes.io/cluster/tienda-eks = shared`
*   `kubernetes.io/role/elb = 1`

---

### Paso 3: Crear el Clúster de EKS y los Workers (AWS Console)
1.  **Clúster (Control Plane):** En la consola de AWS, ve a **EKS** -> **Create Cluster**.
    *   *Nombre:* `tienda-eks`.
    *   *Configuración:* Elige **Configuración personalizada** y asegúrate de **Desactivar el Modo Automático de EKS**.
    *   *IAM Role:* Selecciona `LabEksClusterRole`.
    *   *Redes:* Elige la VPC y las 2 subredes públicas creadas por el script.
    *   *Endpoint Access:* **Public and Private**.
    *   *Logs/Observabilidad:* Habilita todos los logs del plano de control (`api`, `audit`, etc.) y los add-ons (**Metrics Server** y **CloudWatch Observability**).
2.  **Node Group (Workers):** Una vez que el clúster pase a estado `Active` (tarda ~10-15 min), ve a la pestaña **Compute** -> **Add Node Group**.
    *   *Nombre:* `tienda-nodes`.
    *   *IAM Role:* Selecciona `LabEksNodeRole`.
    *   *Computación:* Tipo de capacidad **SPOT** (FinOps) y tipo de instancia **t3.large**.
    *   *Escalado:* Deseado: **1** | Mínimo: **1** | Máximo: **3**.

---

### Paso 4: Subir Imágenes a Amazon ECR (Build & Push)
1.  **Iniciar sesión en Docker ECR:**
    ```powershell
    aws ecr get-login-password --region us-east-1 --no-cli-pager | docker login --username AWS --password-stdin TU_ACCOUNT_ID.dkr.ecr.us-east-1.amazonaws.com
    ```
2.  **Compilar y subir la base de datos (`tienda-db`):**
    ```powershell
    cd db
    docker build -t tienda-db .
    docker tag tienda-db:latest TU_ACCOUNT_ID.dkr.ecr.us-east-1.amazonaws.com/tienda-db:eks-v1
    docker push TU_ACCOUNT_ID.dkr.ecr.us-east-1.amazonaws.com/tienda-db:eks-v1
    cd ..
    ```
3.  **Hacer lo mismo para el `backend` y `frontend`** (entrando en sus respectivas carpetas, compilando, etiquetando con el tag `eks-v1` y subiendo a su repositorio correspondiente).

---

### Paso 5: Despliegue en Kubernetes (EKS)
1.  **Conectar `kubectl` a tu clúster:**
    ```powershell
    aws eks update-kubeconfig --region us-east-1 --name tienda-eks --no-cli-pager
    kubectl get nodes  # Debe mostrar tus nodos en estado 'Ready'
    ```
2.  **Editar manifiestos YAML:** 
    Asegúrate de que en `/k8s/mysql-deployment.yaml`, `/k8s/backend-deployment.yaml` y `/k8s/frontend-deployment.yaml`, la ruta de la propiedad `image` apunte a tu ID de cuenta correcto (`TU_ACCOUNT_ID.dkr.ecr.us-east-1.amazonaws.com/...`).

    #### 💡 Solución de Problemas (LoadBalancer en estado `<pending>` indefinido)
    Si la anotación `service.beta.kubernetes.io/aws-load-balancer-type: "external"` se mantiene en `frontend-service.yaml`, EKS buscará un controlador externo que no tenemos instalado. **Elimina esa anotación** para que EKS cree por defecto un Classic Load Balancer (CLB) nativo de forma inmediata.

3.  **Aplicar manifiestos:**
    ```powershell
    cd k8s
    kubectl apply -f namespace.yaml
    kubectl apply -f mysql-secret.yaml
    kubectl apply -f mysql-deployment.yaml
    kubectl apply -f mysql-service.yaml
    kubectl apply -f backend-deployment.yaml
    kubectl apply -f backend-service.yaml
    kubectl apply -f frontend-deployment.yaml
    kubectl apply -f frontend-service.yaml
    ```
4.  **Obtener URL pública:**
    ```powershell
    kubectl get svc tienda-frontend -n tienda
    ```
    Copia la URL larga de la columna `EXTERNAL-IP` y ábrela en tu navegador para ver la Tienda de Perritos.

---

### Paso 6: Pruebas de Resiliencia SRE

#### A. Autoscaling por carga (HPA)
1.  Aplica las políticas: `kubectl apply -f backend-hpa.yaml`
2.  En una terminal secundaria, deja el monitoreo: `kubectl get hpa -n tienda -w`
3.  Entra a un pod del backend y genera estrés:
    ```powershell
    kubectl exec -it NOMBRE_DEL_POD_BACKEND -n tienda -- sh
    apk add --no-cache curl
    while true; do curl -s http://localhost:3001/api/productos > /dev/null; done
    ```
4.  Verás cómo el HPA escala automáticamente las réplicas del backend de 2 a 8 pods.
5.  Cancela con `Ctrl + C` en la primera terminal y verás cómo el clúster reduce el número de réplicas de forma descendente tras enfriarse.

#### B. Tolerancia a Fallos (Auto-Healing)
*   **A nivel de Pod:** Si eliminas un pod en producción (`kubectl delete pod <nombre> -n tienda`), verás que el ReplicaSet de Kubernetes crea instantáneamente un pod nuevo con otro nombre para mantener la disponibilidad.
*   **A nivel de Contenedor:** Si entras al pod y matas forzosamente todos los procesos de NodeJS (`kill -9 -1`), la consola interactiva se desconectará (código 137). Kubernetes detectará la caída de la aplicación y la livenessProbe activará el reinicio automático del contenedor. Al hacer `kubectl get pods -n tienda` verás que el contador de `RESTARTS` subirá a 1.
