extends Control

@onready var p1_cursor = $Cursors/Player1
@onready var p2_cursor = $Cursors/Player2

@onready var character1 = $Characters/Character1
@onready var character2 = $Characters/Character2

# -1 = Character 1
#  0 = Neutral
#  1 = Character 2
var p1_selection := 0
var p2_selection := 0

var p1_locked := false
var p2_locked := false

var p1_neutral_position: Vector2
var p2_neutral_position: Vector2


func _ready():
	p1_neutral_position = p1_cursor.position
	p2_neutral_position = p2_cursor.position

	update_cursors()


func _process(_delta):
	handle_p1_input()
	handle_p2_input()


func handle_p1_input():

	# Can't move once locked
	if not p1_locked:

		if Input.is_action_just_pressed("LeftP1"):
			var new_selection = p1_selection - 1

			# Don't go past Character 1
			if new_selection >= -1:
				# Don't move onto P2's locked character
				if not (p2_locked and new_selection == p2_selection):
					p1_selection = new_selection
					update_p1_cursor()

		elif Input.is_action_just_pressed("RightP1"):
			var new_selection = p1_selection + 1

			# Don't go past Character 2
			if new_selection <= 1:
				# Don't move onto P2's locked character
				if not (p2_locked and new_selection == p2_selection):
					p1_selection = new_selection
					update_p1_cursor()

	# Lock in
	if Input.is_action_just_pressed("NormalP1"):
		if p1_selection != 0:
			p1_locked = true
			print("P1 locked in character: ", p1_selection)


func handle_p2_input():

	# Can't move once locked
	if not p2_locked:

		if Input.is_action_just_pressed("LeftP2"):
			var new_selection = p2_selection - 1

			# Don't go past Character 1
			if new_selection >= -1:
				# Don't move onto P1's locked character
				if not (p1_locked and new_selection == p1_selection):
					p2_selection = new_selection
					update_p2_cursor()

		elif Input.is_action_just_pressed("RightP2"):
			var new_selection = p2_selection + 1

			# Don't go past Character 2
			if new_selection <= 1:
				# Don't move onto P1's locked character
				if not (p1_locked and new_selection == p1_selection):
					p2_selection = new_selection
					update_p2_cursor()

	# Lock in
	if Input.is_action_just_pressed("NormalP2"):
		if p2_selection != 0:
			p2_locked = true
			print("P2 locked in character: ", p2_selection)


func update_cursors():
	update_p1_cursor()
	update_p2_cursor()


func update_p1_cursor():

	match p1_selection:

		-1:
			p1_cursor.position = get_character_position(character1, p1_cursor)

		0:
			p1_cursor.position = p1_neutral_position

		1:
			p1_cursor.position = get_character_position(character2, p1_cursor)


func update_p2_cursor():

	match p2_selection:

		-1:
			p2_cursor.position = get_character_position(character1, p2_cursor)

		0:
			p2_cursor.position = p2_neutral_position

		1:
			p2_cursor.position = get_character_position(character2, p2_cursor)


func get_character_position(character: ColorRect, cursor: ColorRect) -> Vector2:

	var character_center = character.position + character.size / 2.0

	return character_center - cursor.size / 2.0
