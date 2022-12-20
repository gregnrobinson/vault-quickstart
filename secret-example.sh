# encrypt variable value
vault write transit/encrypt/default plaintext=$(echo "my secret variable" | base64)

# embed vault decrypt using transit engine with cipher text
export SECRET=$(vault write -field=plaintext transit/decrypt/default ciphertext=vault:v1:a/OpmbFLBEmgiTruYez+mUJQuMooKzCOjY0wzJAayMmCyu0BjMnxcLVbjw== | base64 --decode)
