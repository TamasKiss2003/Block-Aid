extends TileMapLayer

func on_player_contact(player: Node2D) -> void:
	player.die()
