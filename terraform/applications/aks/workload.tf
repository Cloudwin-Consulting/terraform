# ------------------------------------------------------------
# Example multi-container workload: the AKS store sample
#
# Four cooperating containers deployed straight from this stack with
# the Kubernetes provider: a RabbitMQ order queue, an order API that
# writes to it, a product API and a store front web app published
# through an internal load balancer. The images are the public sample
# images so the first deployment succeeds before any image has been
# pushed to the registry; point the image variables at the registry
# once application images are published there.
# ------------------------------------------------------------

locals {
  workload_namespace = "store"
  queue_username     = "store-orders"
  queue_name         = "orders"
}

resource "kubernetes_namespace" "store" {
  metadata {
    name = local.workload_namespace
  }
}

# The queue's credentials never appear in source control: generated at
# deployment time, held in this stack's state and a Kubernetes secret,
# and only ever used inside the cluster.
resource "random_password" "queue" {
  length  = 24
  special = false
}

resource "kubernetes_secret" "queue_credentials" {
  metadata {
    name      = "queue-credentials"
    namespace = kubernetes_namespace.store.metadata[0].name
  }

  data = {
    username = local.queue_username
    password = random_password.queue.result
  }
}

# ------------------------------------------------------------
# RabbitMQ - the order queue
#
# Ephemeral by design, like the upstream sample: the queue keeps its
# data in the container filesystem, so a rescheduled pod starts empty.
# Give the stateful set a volume_claim_template backed by the
# cluster's managed-csi storage class where queued orders must survive
# pod replacement.
# ------------------------------------------------------------

resource "kubernetes_stateful_set" "rabbitmq" {
  metadata {
    name      = "rabbitmq"
    namespace = kubernetes_namespace.store.metadata[0].name
  }

  spec {
    service_name = "rabbitmq"
    replicas     = 1

    selector {
      match_labels = {
        app = "rabbitmq"
      }
    }

    template {
      metadata {
        labels = {
          app = "rabbitmq"
        }
      }

      spec {
        node_selector = {
          "kubernetes.io/os" = "linux"
        }

        container {
          name  = "rabbitmq"
          image = var.rabbitmq_image

          port {
            container_port = 5672
            name           = "rabbitmq-amqp"
          }

          port {
            container_port = 15672
            name           = "rabbitmq-http"
          }

          env {
            name = "RABBITMQ_DEFAULT_USER"

            value_from {
              secret_key_ref {
                name = kubernetes_secret.queue_credentials.metadata[0].name
                key  = "username"
              }
            }
          }

          env {
            name = "RABBITMQ_DEFAULT_PASS"

            value_from {
              secret_key_ref {
                name = kubernetes_secret.queue_credentials.metadata[0].name
                key  = "password"
              }
            }
          }

          resources {
            requests = {
              cpu    = "10m"
              memory = "128Mi"
            }
            limits = {
              cpu    = "250m"
              memory = "256Mi"
            }
          }

          startup_probe {
            tcp_socket {
              port = "5672"
            }

            failure_threshold     = 30
            initial_delay_seconds = 10
            period_seconds        = 10
          }

          readiness_probe {
            tcp_socket {
              port = "5672"
            }

            failure_threshold     = 3
            initial_delay_seconds = 5
            period_seconds        = 5
          }

          liveness_probe {
            tcp_socket {
              port = "5672"
            }

            failure_threshold     = 3
            initial_delay_seconds = 30
            period_seconds        = 10
          }
        }
      }
    }
  }
}

resource "kubernetes_service" "rabbitmq" {
  metadata {
    name      = "rabbitmq"
    namespace = kubernetes_namespace.store.metadata[0].name
  }

  spec {
    type = "ClusterIP"

    selector = {
      app = "rabbitmq"
    }

    port {
      name        = "rabbitmq-amqp"
      port        = 5672
      target_port = 5672
    }

    port {
      name        = "rabbitmq-http"
      port        = 15672
      target_port = 15672
    }
  }
}

# ------------------------------------------------------------
# Order service - takes orders from the store front and writes them to
# the queue
# ------------------------------------------------------------

resource "kubernetes_deployment" "order_service" {
  metadata {
    name      = "order-service"
    namespace = kubernetes_namespace.store.metadata[0].name
  }

  spec {
    replicas = var.order_service_replicas

    selector {
      match_labels = {
        app = "order-service"
      }
    }

    template {
      metadata {
        labels = {
          app = "order-service"
        }
      }

      spec {
        node_selector = {
          "kubernetes.io/os" = "linux"
        }

        # Hold the service back until the queue accepts connections, so
        # its first health checks pass.
        init_container {
          name    = "wait-for-rabbitmq"
          image   = var.wait_for_queue_image
          command = ["sh", "-c", "until nc -zv rabbitmq 5672; do echo waiting for rabbitmq; sleep 2; done;"]

          resources {
            requests = {
              cpu    = "1m"
              memory = "50Mi"
            }
            limits = {
              cpu    = "75m"
              memory = "128Mi"
            }
          }
        }

        container {
          name  = "order-service"
          image = var.order_service_image

          port {
            container_port = 3000
          }

          env {
            name  = "ORDER_QUEUE_HOSTNAME"
            value = kubernetes_service.rabbitmq.metadata[0].name
          }

          env {
            name  = "ORDER_QUEUE_PORT"
            value = "5672"
          }

          env {
            name = "ORDER_QUEUE_USERNAME"

            value_from {
              secret_key_ref {
                name = kubernetes_secret.queue_credentials.metadata[0].name
                key  = "username"
              }
            }
          }

          env {
            name = "ORDER_QUEUE_PASSWORD"

            value_from {
              secret_key_ref {
                name = kubernetes_secret.queue_credentials.metadata[0].name
                key  = "password"
              }
            }
          }

          env {
            name  = "ORDER_QUEUE_NAME"
            value = local.queue_name
          }

          env {
            name  = "FASTIFY_ADDRESS"
            value = "0.0.0.0"
          }

          resources {
            requests = {
              cpu    = "1m"
              memory = "50Mi"
            }
            limits = {
              cpu    = "75m"
              memory = "128Mi"
            }
          }

          startup_probe {
            http_get {
              path = "/health"
              port = "3000"
            }

            failure_threshold     = 5
            initial_delay_seconds = 20
            period_seconds        = 10
          }

          readiness_probe {
            http_get {
              path = "/health"
              port = "3000"
            }

            failure_threshold     = 3
            initial_delay_seconds = 3
            period_seconds        = 5
          }

          liveness_probe {
            http_get {
              path = "/health"
              port = "3000"
            }

            failure_threshold     = 5
            initial_delay_seconds = 3
            period_seconds        = 3
          }
        }
      }
    }
  }
}

resource "kubernetes_service" "order_service" {
  metadata {
    name      = "order-service"
    namespace = kubernetes_namespace.store.metadata[0].name
  }

  spec {
    type = "ClusterIP"

    selector = {
      app = "order-service"
    }

    port {
      name        = "http"
      port        = 3000
      target_port = 3000
    }
  }
}

# ------------------------------------------------------------
# Product service - serves the product catalogue
# ------------------------------------------------------------

resource "kubernetes_deployment" "product_service" {
  metadata {
    name      = "product-service"
    namespace = kubernetes_namespace.store.metadata[0].name
  }

  spec {
    replicas = var.product_service_replicas

    selector {
      match_labels = {
        app = "product-service"
      }
    }

    template {
      metadata {
        labels = {
          app = "product-service"
        }
      }

      spec {
        node_selector = {
          "kubernetes.io/os" = "linux"
        }

        container {
          name  = "product-service"
          image = var.product_service_image

          port {
            container_port = 3002
          }

          resources {
            requests = {
              cpu    = "1m"
              memory = "1Mi"
            }
            limits = {
              cpu    = "2m"
              memory = "20Mi"
            }
          }

          readiness_probe {
            http_get {
              path = "/health"
              port = "3002"
            }

            failure_threshold     = 3
            initial_delay_seconds = 3
            period_seconds        = 5
          }

          liveness_probe {
            http_get {
              path = "/health"
              port = "3002"
            }

            failure_threshold     = 5
            initial_delay_seconds = 3
            period_seconds        = 3
          }
        }
      }
    }
  }
}

resource "kubernetes_service" "product_service" {
  metadata {
    name      = "product-service"
    namespace = kubernetes_namespace.store.metadata[0].name
  }

  spec {
    type = "ClusterIP"

    selector = {
      app = "product-service"
    }

    port {
      name        = "http"
      port        = 3002
      target_port = 3002
    }
  }
}

# ------------------------------------------------------------
# Store front - the web shop, proxying to the order and product
# services by their service names
# ------------------------------------------------------------

resource "kubernetes_deployment" "store_front" {
  metadata {
    name      = "store-front"
    namespace = kubernetes_namespace.store.metadata[0].name
  }

  # The image's NGINX configuration resolves the order-service and
  # product-service upstream names at startup, so those Service objects
  # must exist first. The reference lives inside the image, invisible
  # to Terraform - hence the explicit dependency.
  depends_on = [
    kubernetes_service.order_service,
    kubernetes_service.product_service,
  ]

  spec {
    replicas = var.store_front_replicas

    selector {
      match_labels = {
        app = "store-front"
      }
    }

    template {
      metadata {
        labels = {
          app = "store-front"
        }
      }

      spec {
        node_selector = {
          "kubernetes.io/os" = "linux"
        }

        container {
          name  = "store-front"
          image = var.store_front_image

          port {
            container_port = 8080
            name           = "store-front"
          }

          resources {
            requests = {
              cpu    = "1m"
              memory = "200Mi"
            }
            limits = {
              cpu    = "1000m"
              memory = "512Mi"
            }
          }

          startup_probe {
            http_get {
              path = "/health"
              port = "8080"
            }

            failure_threshold     = 3
            initial_delay_seconds = 5
            period_seconds        = 5
          }

          readiness_probe {
            http_get {
              path = "/health"
              port = "8080"
            }

            failure_threshold     = 3
            initial_delay_seconds = 3
            period_seconds        = 3
          }

          liveness_probe {
            http_get {
              path = "/health"
              port = "8080"
            }

            failure_threshold     = 5
            initial_delay_seconds = 3
            period_seconds        = 3
          }
        }
      }
    }
  }
}

# The shop's entry point: a load balancer service whose frontend takes
# a private address in the spoke's AKS subnet, so the store front is
# only reachable from inside the network - directly, or through the
# entry points that publish it (see ingress.tf).
#
# store_front_load_balancer_ip pins that address. Left null the cluster
# takes any free one, which is fine for a workload reached by name from
# inside the cluster, but leaves nothing outside able to name it: the
# spoke's application gateway deploys before this stack and has to be
# given a fixed address, and the private link service selects the
# frontend to publish by address. Setting it on a running deployment
# moves the frontend, which interrupts traffic briefly.
resource "kubernetes_service" "store_front" {
  metadata {
    name      = "store-front"
    namespace = kubernetes_namespace.store.metadata[0].name

    annotations = merge(
      {
        "service.beta.kubernetes.io/azure-load-balancer-internal" = "true"
      },
      var.store_front_load_balancer_ip == null ? {} : {
        "service.beta.kubernetes.io/azure-load-balancer-ipv4" = var.store_front_load_balancer_ip
      }
    )
  }

  spec {
    type = "LoadBalancer"

    selector = {
      app = "store-front"
    }

    port {
      port        = 80
      target_port = 8080
    }
  }

  lifecycle {
    precondition {
      # An address sits inside a prefix when the two share a network
      # address at the prefix's length - and has to be one Azure will
      # hand out, which rules out the four addresses it reserves at the
      # start of every subnet and the one at the end. Azure rejects
      # both at apply time; this says so at plan time.
      #
      # The null opt-out is a conditional rather than the left side of
      # an ||: Terraform evaluates both operands of ||, so the address
      # arithmetic would still run against null and fail the plan for
      # the very configurations the default is meant to leave alone.
      # try() then makes a malformed address "no match" instead of an
      # error, so it reaches the message below rather than a stack trace.
      condition = var.store_front_load_balancer_ip == null ? true : anytrue([
        for prefix in data.azurerm_subnet.aks.address_prefixes : try(
          cidrhost("${var.store_front_load_balancer_ip}/${split("/", prefix)[1]}", 0) == cidrhost(prefix, 0)
          && !contains([
            cidrhost(prefix, 0),
            cidrhost(prefix, 1),
            cidrhost(prefix, 2),
            cidrhost(prefix, 3),
            cidrhost(prefix, -1),
          ], var.store_front_load_balancer_ip),
          false
        )
      ])
      error_message = "store_front_load_balancer_ip (${coalesce(var.store_front_load_balancer_ip, "null")}) must be a usable address of the AKS subnet ${join(", ", data.azurerm_subnet.aks.address_prefixes)}: the cluster's internal load balancer frontend takes its address from that subnet, and Azure reserves the first four addresses and the last of every subnet."
    }
  }
}
