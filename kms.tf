resource "aws_kms_external_key" "this" {
  for_each = local.create_keys ? var.key_versions : []

  description             = "${var.name} GitHub App ${var.github_app_id} signing key (${each.key})"
  key_spec                = "RSA_2048"
  key_usage               = "SIGN_VERIFY"
  deletion_window_in_days = var.key_deletion_window_in_days
  policy                  = data.aws_iam_policy_document.key.json

  # key_material_base64 is deliberately never set: it would put the App key in
  # state. Material is imported out of band with scripts/import-key-material.sh.

  tags = var.tags
}

resource "aws_kms_alias" "this" {
  count = local.create_keys ? 1 : 0

  name          = "alias/${var.name}"
  target_key_id = aws_kms_external_key.this[var.active_key_version].id
}

data "aws_iam_policy_document" "key" {
  statement {
    sid       = "Sign"
    actions   = ["kms:Sign"]
    resources = ["*"]

    principals {
      type        = "AWS"
      identifiers = local.signer_role_arns
    }
  }

  statement {
    sid = "BreakGlassAdministration"
    actions = [
      "kms:CancelKeyDeletion",
      "kms:DeleteImportedKeyMaterial",
      "kms:Describe*",
      "kms:DisableKey",
      "kms:EnableKey",
      "kms:Get*",
      "kms:ImportKeyMaterial",
      "kms:List*",
      "kms:PutKeyPolicy",
      "kms:ScheduleKeyDeletion",
      "kms:TagResource",
      "kms:UntagResource",
      "kms:UpdateAlias",
      "kms:UpdateKeyDescription",
    ]
    resources = ["*"]

    principals {
      type        = "AWS"
      identifiers = [var.key_admin_role_arn]
    }
  }

  statement {
    sid = "DeployerManagement"
    actions = [
      "kms:CreateAlias",
      "kms:DeleteAlias",
      "kms:Describe*",
      "kms:Get*",
      "kms:List*",
      "kms:PutKeyPolicy",
      "kms:ScheduleKeyDeletion",
      "kms:TagResource",
      "kms:UntagResource",
      "kms:UpdateAlias",
      "kms:UpdateKeyDescription",
    ]
    resources = ["*"]

    principals {
      type        = "AWS"
      identifiers = [local.key_deployer_role_arn]
    }
  }
}
