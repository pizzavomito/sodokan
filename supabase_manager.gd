extends Node

# ── Configuration Supabase ──────────────────────────────────────────────────
# 1. Crée un projet sur https://supabase.com
# 2. Dans SQL Editor, exécute ce script EN ENTIER :
#	 
#    DROP TABLE IF EXISTS scores CASCADE;
#	 
#    CREATE TABLE scores (
#      id          BIGSERIAL PRIMARY KEY,
#      player_id   TEXT    NOT NULL,          -- UUID unique par device
#      player_name TEXT    NOT NULL,          -- Nom affiché (peut être dupliqué)
#      level_index INTEGER NOT NULL,
#      level_name  TEXT    DEFAULT '',
#      moves       INTEGER NOT NULL,
#      time_ms     INTEGER NOT NULL,
#      created_at  TIMESTAMPTZ DEFAULT NOW(),
#      CONSTRAINT scores_device_level_unique UNIQUE (player_id, level_index)
#    );
#    ALTER TABLE scores ENABLE ROW LEVEL SECURITY;
#    CREATE POLICY "read_all"   ON scores FOR SELECT USING (true);
#    CREATE POLICY "upsert_all" ON scores FOR ALL USING (true) WITH CHECK (true);
#
#    -- Supprime l'ancienne version si elle existe (signature différente)
#    DROP FUNCTION IF EXISTS submit_best_score(TEXT, INTEGER, TEXT, INTEGER, INTEGER);
#
#    -- Fonction RPC : insère ou met à jour uniquement si le score est meilleur
#    -- La clé de déduplication est player_id (pas le nom, qui peut être dupliqué)
#    CREATE OR REPLACE FUNCTION submit_best_score(
#      p_player_id   TEXT,
#      p_player_name TEXT,
#      p_level_index INTEGER,
#      p_level_name  TEXT,
#      p_moves       INTEGER,
#      p_time_ms     INTEGER
#    ) RETURNS void LANGUAGE plpgsql AS $$
#    BEGIN
#      INSERT INTO scores (player_id, player_name, level_index, level_name, moves, time_ms)
#      VALUES (p_player_id, p_player_name, p_level_index, p_level_name, p_moves, p_time_ms)
#      ON CONFLICT (player_id, level_index) DO UPDATE SET
#        player_name = EXCLUDED.player_name,
#        moves       = EXCLUDED.moves,
#        time_ms     = EXCLUDED.time_ms,
#        level_name  = EXCLUDED.level_name,
#        created_at  = NOW()
#      WHERE
#        EXCLUDED.moves < scores.moves
#        OR (EXCLUDED.moves = scores.moves AND EXCLUDED.time_ms < scores.time_ms);
#    END;
#    $$;
#    GRANT EXECUTE ON FUNCTION submit_best_score TO anon;
#
# 3. Remplace les deux constantes ci-dessous (Settings > API dans le dashboard)

const SUPABASE_URL     = "https://bgzygxwytvytqtguozrq.supabase.co"
const SUPABASE_ANON_KEY = "sb_publishable_VvkI8bj6e-FetcINBmqfXA_wsCcLB4J"

signal score_submitted(success: bool)
signal leaderboard_received(entries: Array)

var _http_submit: HTTPRequest
var _http_leaderboard: HTTPRequest

func _ready():
	_http_submit = HTTPRequest.new()
	_http_submit.timeout = 10.0
	_http_leaderboard = HTTPRequest.new()
	_http_leaderboard.timeout = 10.0
	add_child(_http_submit)
	add_child(_http_leaderboard)
	_http_submit.request_completed.connect(_on_submit_completed)
	_http_leaderboard.request_completed.connect(_on_leaderboard_completed)

func is_configured() -> bool:
	return SUPABASE_URL != "https://VOTRE_PROJET.supabase.co" \
		and SUPABASE_ANON_KEY != "VOTRE_ANON_KEY"

func submit_score(level_index: int, level_name: String, moves: int, time_ms: int, player_name: String, player_id: String) -> void:
	if not is_configured():
		score_submitted.emit(false)
		return

	var url = SUPABASE_URL + "/rest/v1/rpc/submit_best_score"
	var headers = PackedStringArray([
		"apikey: " + SUPABASE_ANON_KEY,
		"Authorization: Bearer " + SUPABASE_ANON_KEY,
		"Content-Type: application/json",
	])
	var body = JSON.stringify({
		"p_player_id":   player_id,
		"p_player_name": player_name,
		"p_level_index": level_index,
		"p_level_name":  level_name,
		"p_moves":       moves,
		"p_time_ms":     time_ms,
	})

	var err = _http_submit.request(url, headers, HTTPClient.METHOD_POST, body)
	if err != OK:
		score_submitted.emit(false)

func get_leaderboard(level_index: int) -> void:
	if not is_configured():
		leaderboard_received.emit([])
		return

	var url = SUPABASE_URL \
		+ "/rest/v1/scores?level_index=eq." + str(level_index) \
		+ "&order=moves.asc,time_ms.asc&limit=10" \
		+ "&select=player_id,player_name,moves,time_ms"
	var headers = PackedStringArray([
		"apikey: " + SUPABASE_ANON_KEY,
		"Authorization: Bearer " + SUPABASE_ANON_KEY,
	])

	var err = _http_leaderboard.request(url, headers)
	if err != OK:
		leaderboard_received.emit([])

func _on_submit_completed(result: int, response_code: int, _headers: PackedStringArray, _body: PackedByteArray) -> void:
	var ok = result == HTTPRequest.RESULT_SUCCESS \
		and (response_code == 200 or response_code == 201 or response_code == 204)
	score_submitted.emit(ok)

func _on_leaderboard_completed(result: int, response_code: int, _headers: PackedStringArray, body: PackedByteArray) -> void:
	if result == HTTPRequest.RESULT_SUCCESS and response_code == 200:
		var parsed = JSON.parse_string(body.get_string_from_utf8())
		leaderboard_received.emit(parsed if parsed is Array else [])
	else:
		leaderboard_received.emit([])
