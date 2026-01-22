import Config

config :scenic, :assets, module: ZfsMeter.Assets
config :zfs_meter, color_scheme: :sunny_day

config :zfs_meter, :viewport,
  name: :main_viewport,
  size: {2388, 1668},
  default_scene: ZfsMeter.Scene.Main,
  drivers: [
    [
      module: Scenic.Driver.Local,
      name: :local,
      window: [title: "ALIC II", resizeable: false]
    ]
  ]
