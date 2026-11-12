extends SceneTree
## Renderer smoke only. Core commands drive real World routes, not player acceptance.
const UI=preload("res://tests/barbecue_ui_fixture.gd")
var game:Node
func _initialize()->void:call_deferred("run")
func walk(at:Vector2)->void:
 assert(game.world.command("human",{"intent":"move","x":at.x,"y":at.y}).ok)
 for tick in range(3000):
  game._process(.1);game.view._process(.1)
  if not game.world._routes.has("human"):break
func shot(name:String)->void:
 game.view.queue_redraw();await process_frame;await RenderingServer.frame_post_draw
 root.get_texture().get_image().save_png(OS.get_environment("HABITAT_MOTION_EVIDENCE").path_join(name+".png"))
func run()->void:
 game=UI.init_game(self);await process_frame;await process_frame
 var d:RefCounted=game.world.dark
 walk(d.p(d.config.home_arrival));assert(d.travel([]).ok)
 game.view.show_region("dark");game.view.center=game.world.point(game.world.actors.human);game.view.follow_player=true;game.view._process(.01)
 await shot("dark-dock")
 assert(d.start("torch",d.p(d.config.camp)).ok)
 for tick in range(500):
  game._process(.05);game.view._process(.05)
  if d.pending.is_empty():break
 assert(d.torch.remaining>0)
 walk(Vector2(47,82));game.view.center=game.world.point(game.world.actors.human);game.view.follow_player=true;game.view._process(.01)
 print("FOG camera=",game.view.center," zoom=",game.view.zoom," player=",game.world.point(game.world.actors.human)," uniform=",game.view.dark_renderer.overlay.fog.material.get_shader_parameter("personal_center")," size=",game.view.dark_renderer.overlay.fog.size)
 await shot("dark-torch")
 game.queue_free();await process_frame;print("Dark renderer viewport smoke passed; core routes, separate from mouse acceptance");quit()
