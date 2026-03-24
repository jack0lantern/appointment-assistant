class RenameUsersPasswordHashToPasswordDigest < ActiveRecord::Migration[7.2]
  def up
    return unless column_exists?(:users, :password_hash)
    return if column_exists?(:users, :password_digest)

    rename_column :users, :password_hash, :password_digest
  end

  def down
    return unless column_exists?(:users, :password_digest)
    return if column_exists?(:users, :password_hash)

    rename_column :users, :password_digest, :password_hash
  end
end
