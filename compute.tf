data "aws_ami" "al2023" {
  most_recent = true
  owners      = ["amazon"]

  filter {
    name   = "name"
    values = ["al2023-ami-*-kernel-*-arm64"]
  }

  filter {
    name   = "architecture"
    values = ["arm64"]
  }
}

resource "aws_iam_role" "ec2_ssm" {
  name = "${var.project_name}-${var.environment}-ec2-ssm-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17",
    Statement = [{
      Effect    = "Allow",
      Principal = { Service = "ec2.amazonaws.com" },
      Action    = "sts:AssumeRole"
    }]
  })
}

resource "aws_iam_role_policy_attachment" "ec2_ssm_core" {
  role       = aws_iam_role.ec2_ssm.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

resource "aws_iam_instance_profile" "ec2_ssm" {
  name = "${var.project_name}-${var.environment}-ec2-ssm-profile"
  role = aws_iam_role.ec2_ssm.name
}

resource "aws_security_group" "app" {
  name        = "${var.project_name}-${var.environment}-app-sg"
  description = "App instance security group (no inbound from internet)"
  vpc_id      = aws_vpc.main.id

  # No inbound rules yet (we'll add ALB -> instance later)

  egress {
    description = "Allow outbound (required for VPC endpoints and package installs if you add NAT later)"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "${var.project_name}-${var.environment}-app-sg"
  }
}

resource "aws_instance" "app" {
  ami                    = data.aws_ami.al2023.id
  instance_type          = "t4g.micro"
  subnet_id              = aws_subnet.private[0].id
  vpc_security_group_ids = [aws_security_group.app.id]
  iam_instance_profile   = aws_iam_instance_profile.ec2_ssm.name

  user_data_replace_on_change = true
  user_data                   = <<-EOF
#!/bin/bash
set -euo pipefail

mkdir -p /home/ec2-user/nz-demo
cat > /home/ec2-user/nz-demo/index.html <<'HTML'
<html>
  <head><title>Cloud Baseline</title></head>
  <body>
    <h1>Cloud Baseline</h1>
    <p>Private EC2 behind ALB, managed via SSM (no SSH, no NAT).</p>
  </body>
</html>
HTML
chown -R ec2-user:ec2-user /home/ec2-user/nz-demo

cat > /etc/systemd/system/nz-demo.service <<'UNIT'
[Unit]
Description=Cloud Baseline demo web server
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
User=ec2-user
WorkingDirectory=/home/ec2-user/nz-demo
ExecStart=/usr/bin/python3 -m http.server 8080 --bind 0.0.0.0
Restart=always

[Install]
WantedBy=multi-user.target
UNIT

systemctl daemon-reload
systemctl enable --now nz-demo
EOF

  metadata_options {
    http_tokens = "required"
  }

  tags = {
    Name = "${var.project_name}-${var.environment}-app-1"
    Role = "app"
  }
}

