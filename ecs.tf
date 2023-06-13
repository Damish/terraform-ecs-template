resource "aws_ecs_cluster" "test-cluster" {
  name = "tf-myapp-cluster"
}

data "template_file" "testapp" {
  template = file("./templates/image/image.json")

  vars = {
    app_image      = var.app_image
    app_port       = var.app_port
    fargate_cpu    = var.fargate_cpu
    fargate_memory = var.fargate_memory
    aws_region     = var.aws_region
  }
}

resource "aws_efs_file_system" "test-efs" {
  creation_token = "tf-test-ecs-efs"
}

resource "aws_efs_mount_target" "mount" {
  count           = 2
  file_system_id  = aws_efs_file_system.test-efs.id
  subnet_id       = aws_subnet.private[count.index].id
  security_groups = [aws_security_group.efs_sg.id]

  depends_on = [
    aws_efs_file_system.test-efs,
    aws_security_group.efs_sg
  ]
}

resource "aws_efs_access_point" "efs-access-point" {
  file_system_id = aws_efs_file_system.test-efs.id
  depends_on = [
    aws_efs_file_system.test-efs
  ]
}

resource "aws_ecs_task_definition" "test-def" {
  family                   = "tf-testapp-task"
  execution_role_arn       = aws_iam_role.ecs_task_execution_role.arn
  network_mode             = "awsvpc"
  requires_compatibilities = ["FARGATE"]
  cpu                      = var.fargate_cpu
  memory                   = var.fargate_memory
  container_definitions    = data.template_file.testapp.rendered

  volume {
    name = "tf-efs-volume"
    efs_volume_configuration {
      file_system_id = "${aws_efs_file_system.test-efs.id}"
      transit_encryption = "ENABLED"
      transit_encryption_port = 2999
      authorization_config {
        access_point_id = aws_efs_access_point.efs-access-point.id
      }
    }
  }

  depends_on = [
    aws_efs_file_system.test-efs,
    aws_efs_access_point.efs-access-point
  ]
}

resource "aws_ecs_service" "test-service" {
  name            = "tf-testapp-service"
  cluster         = aws_ecs_cluster.test-cluster.id
  task_definition = aws_ecs_task_definition.test-def.arn
  desired_count   = var.app_count
  launch_type     = "FARGATE"

  network_configuration {
    security_groups = [
      aws_security_group.ecs_sg.id,
      aws_security_group.efs_sg.id
    ]
    subnets          = aws_subnet.private.*.id
    assign_public_ip = true
  }

  load_balancer {
    target_group_arn = aws_alb_target_group.myapp-tg.arn
    container_name   = "testapp"
    container_port   = var.app_port
  }

  depends_on = [aws_alb_listener.testapp, aws_iam_role_policy_attachment.ecs_task_execution_role]
}