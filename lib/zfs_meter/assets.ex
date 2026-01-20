defmodule ZfsMeter.Assets do
  use Scenic.Assets.Static,
    otp_app: :zfs_meter,
    sources: [
      # Include Scenic's default fonts
      {:scenic, "deps/scenic/assets"}
    ]
end
