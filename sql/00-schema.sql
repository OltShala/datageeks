--
-- PostgreSQL database dump
--

\restrict kG3GgPzoxGxuEYAocSX2xvZOlrtVRgPGxolZhRUJ8jrlQtS701k1k196kGcmO6V

-- Dumped from database version 15.18 (Debian 15.18-1.pgdg12+1)
-- Dumped by pg_dump version 15.18 (Debian 15.18-1.pgdg12+1)

SET statement_timeout = 0;
SET lock_timeout = 0;
SET idle_in_transaction_session_timeout = 0;
SET client_encoding = 'UTF8';
SET standard_conforming_strings = on;
SELECT pg_catalog.set_config('search_path', '', false);
SET check_function_bodies = false;
SET xmloption = content;
SET client_min_messages = warning;
SET row_security = off;

--
-- Name: btree_gist; Type: EXTENSION; Schema: -; Owner: -
--

CREATE EXTENSION IF NOT EXISTS btree_gist WITH SCHEMA public;


--
-- Name: EXTENSION btree_gist; Type: COMMENT; Schema: -; Owner: -
--

COMMENT ON EXTENSION btree_gist IS 'support for indexing common datatypes in GiST';


--
-- Name: receply_book(jsonb); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.receply_book(p jsonb) RETURNS jsonb
    LANGUAGE plpgsql
    AS $_$
DECLARE
  acct int  := receply_resolve_account(p);
  room text := nullif(btrim(coalesce(p->>'room_number', '')), '');
  ci   date := CASE WHEN p->>'check_in'  ~ '^\d{4}-\d{2}-\d{2}' THEN left(p->>'check_in', 10)::date END;
  co   date := CASE WHEN p->>'check_out' ~ '^\d{4}-\d{2}-\d{2}' THEN left(p->>'check_out', 10)::date END;
  tkt  text := nullif(upper(btrim(coalesce(p->>'ticket', ''))), '');
  em   text := nullif(lower(btrim(coalesce(p->>'email', ''))), '');
  g bigint; r bigint;
BEGIN
  IF acct IS NULL THEN
    RETURN jsonb_build_object('ok', false, 'reason', 'no_account', 'message', 'This conversation is not linked to a registered hotel, so nothing can be booked. Nothing was saved. Offer to connect the guest with a person.');
  END IF;
  IF room IS NULL OR ci IS NULL OR co IS NULL OR co <= ci OR tkt IS NULL THEN
    RETURN jsonb_build_object('ok', false, 'reason', 'bad_input', 'message', 'A room number, a ticket, and a check-in date before the check-out date (YYYY-MM-DD) are required. Nothing was saved.');
  END IF;
  IF NOT EXISTS (SELECT 1 FROM receply_rooms WHERE account_id = acct AND room_number = room AND active) THEN
    RETURN jsonb_build_object('ok', false, 'reason', 'unknown_room', 'message', 'Room ' || room || ' does not exist at this hotel. Nothing was saved. Use a room number returned by "Get row Information Hotel Rooms".');
  END IF;
  BEGIN
    IF em IS NOT NULL THEN
      INSERT INTO receply_guests (account_id, first_name, last_name, phone, email)
      VALUES (acct, p->>'first_name', p->>'last_name', p->>'phone', em)
      ON CONFLICT (account_id, lower(email)) WHERE coalesce(email, '') <> ''
      DO UPDATE SET first_name = coalesce(nullif(EXCLUDED.first_name, ''), receply_guests.first_name),
                    last_name  = coalesce(nullif(EXCLUDED.last_name, ''),  receply_guests.last_name),
                    phone      = coalesce(nullif(EXCLUDED.phone, ''),      receply_guests.phone),
                    updated_at = now()
      RETURNING id INTO g;
    ELSE
      INSERT INTO receply_guests (account_id, first_name, last_name, phone) VALUES (acct, p->>'first_name', p->>'last_name', p->>'phone') RETURNING id INTO g;
    END IF;
    INSERT INTO receply_reservations (account_id, booking_no, ticket, guest_id, room_number, check_in, check_out, check_in_at, check_out_at,
                                      status, conversation_id, channel, whatsapp_phone, source)
    VALUES (acct, CASE WHEN p->>'booking_no' ~ '^\d+$' THEN (p->>'booking_no')::int END, tkt, g, room, ci, co,
            CASE WHEN p->>'check_in_at'  ~ '^\d{4}-' THEN (p->>'check_in_at')::timestamptz END,
            CASE WHEN p->>'check_out_at' ~ '^\d{4}-' THEN (p->>'check_out_at')::timestamptz END,
            'confirmed', CASE WHEN p->>'conversation_id' ~ '^\d+$' THEN (p->>'conversation_id')::int END,
            nullif(p->>'channel', ''), nullif(p->>'whatsapp_phone', ''), 'ai')
    RETURNING id INTO r;
  EXCEPTION
    WHEN exclusion_violation THEN
      RETURN jsonb_build_object('ok', false, 'reason', 'room_taken', 'message', 'Room ' || room || ' is already booked for part of ' || ci || ' to ' || co || '. Nothing was saved. Check another suitable room with "Check Availability".');
    WHEN unique_violation THEN
      RETURN jsonb_build_object('ok', false, 'reason', 'duplicate_ticket', 'message', 'Ticket ' || tkt || ' is already used. Nothing was saved. Generate a new ID and ticket first.');
  END;
  RETURN jsonb_build_object('ok', true, 'reservation_id', r, 'account_id', acct, 'ticket', tkt, 'room', room, 'check_in', ci, 'check_out', co);
END $_$;


--
-- Name: receply_cancel(jsonb); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.receply_cancel(p jsonb) RETURNS jsonb
    LANGUAGE plpgsql
    AS $$
DECLARE
  acct   int  := receply_resolve_account(p);
  tkt    text := upper(btrim(coalesce(p->>'ticket', '')));
  digits text := regexp_replace(coalesce(p->>'phone', ''), '\D', '', 'g');
  nm     text := lower(regexp_replace(btrim(coalesce(p->>'name', '')), '\s+', ' ', 'g'));
  hit    record;
BEGIN
  IF acct IS NULL THEN
    RETURN jsonb_build_object('ok', false, 'reason', 'no_account', 'message', 'This conversation is not linked to a registered hotel. Nothing was cancelled.');
  END IF;
  IF tkt <> '' THEN
    SELECT r.id, r.ticket, r.calendar_event_id, r.room_number, r.check_in, r.check_out, g.first_name, g.last_name INTO hit
      FROM receply_reservations r LEFT JOIN receply_guests g ON g.id = r.guest_id
     WHERE r.account_id = acct AND upper(r.ticket) = tkt AND r.status = 'confirmed';
  ELSIF length(digits) >= 6 AND nm <> '' THEN
    SELECT r.id, r.ticket, r.calendar_event_id, r.room_number, r.check_in, r.check_out, g.first_name, g.last_name INTO hit
      FROM receply_reservations r JOIN receply_guests g ON g.id = r.guest_id
     WHERE r.account_id = acct AND r.status = 'confirmed'
       AND right(g.phone_digits, 8) = right(digits, 8)
       AND lower(regexp_replace(btrim(coalesce(g.first_name, '') || ' ' || coalesce(g.last_name, '')), '\s+', ' ', 'g')) = nm
     ORDER BY (r.check_out < current_date), r.check_in
     LIMIT 1;
  ELSE
    RETURN jsonb_build_object('ok', false, 'reason', 'need_identity', 'message', 'Nothing was cancelled. Ask the guest for the ticket number, or for BOTH the phone number and the full name used on the booking.');
  END IF;
  IF hit.id IS NULL THEN
    RETURN jsonb_build_object('ok', false, 'reason', 'not_found', 'message', 'No active reservation matches those details, so nothing was cancelled. Do NOT say it was cancelled. Ask the guest to check the ticket number, or offer to connect them with a person.');
  END IF;
  UPDATE receply_reservations SET status = 'cancelled', cancelled_at = now(), updated_at = now() WHERE id = hit.id;
  RETURN jsonb_build_object('ok', true, 'reservation_id', hit.id, 'ticket', hit.ticket, 'calendar_event_id', coalesce(hit.calendar_event_id, ''),
    'guest', btrim(coalesce(hit.first_name, '') || ' ' || coalesce(hit.last_name, '')), 'room', hit.room_number,
    'check_in', hit.check_in, 'check_out', hit.check_out);
END $$;


--
-- Name: receply_cancel_v2(jsonb); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.receply_cancel_v2(p jsonb) RETURNS jsonb
    LANGUAGE plpgsql
    AS $_$
DECLARE
  acct   int  := receply_resolve_account(p);
  tkt    text := upper(btrim(coalesce(p->>'ticket', '')));
  digits text := regexp_replace(coalesce(p->>'phone', ''), '\D', '', 'g');
  nm     text := lower(regexp_replace(btrim(coalesce(p->>'name', '')), '\s+', ' ', 'g'));
  turn   text := nullif(btrim(coalesce(p->>'turn', '')), '');
  step   text := lower(btrim(coalesce(p->>'step', '')));   -- 'request' never cancels; 'confirm' (or none) may
  conv   int  := CASE WHEN p->>'conversation_id' ~ '^\d+$' THEN (p->>'conversation_id')::int END;
  hit record; c record;
BEGIN
  IF acct IS NULL THEN
    RETURN jsonb_build_object('ok', false, 'reason', 'no_account', 'message', 'This conversation is not linked to a registered hotel. Nothing was cancelled.');
  END IF;
  IF tkt <> '' THEN
    SELECT r.*, g.first_name, g.last_name, g.email AS guest_email INTO hit
      FROM receply_reservations r LEFT JOIN receply_guests g ON g.id = r.guest_id
     WHERE r.account_id = acct AND upper(r.ticket) = tkt AND r.status = 'confirmed';
  ELSIF length(digits) >= 6 AND nm <> '' THEN
    SELECT r.*, g.first_name, g.last_name, g.email AS guest_email INTO hit
      FROM receply_reservations r JOIN receply_guests g ON g.id = r.guest_id
     WHERE r.account_id = acct AND r.status = 'confirmed'
       AND right(g.phone_digits, 8) = right(digits, 8)
       AND lower(regexp_replace(btrim(coalesce(g.first_name, '') || ' ' || coalesce(g.last_name, '')), '\s+', ' ', 'g')) = nm
     ORDER BY (r.check_out < current_date), r.check_in
     LIMIT 1;
  ELSE
    RETURN jsonb_build_object('ok', false, 'reason', 'need_identity', 'message', 'Nothing was cancelled. Ask the guest for the ticket number, or for BOTH the phone number and the full name used on the booking.');
  END IF;
  IF hit.id IS NULL THEN
    RETURN jsonb_build_object('ok', false, 'reason', 'not_found', 'message', 'No active reservation matches those details, so nothing was cancelled. Do NOT say it was cancelled. Ask the guest to check the ticket number, or offer to connect them with a person.');
  END IF;
  IF step = 'request' OR turn IS NULL OR hit.cancel_request_turn IS NULL OR hit.cancel_request_turn = turn OR hit.cancel_requested_at < now() - interval '30 minutes' THEN
    UPDATE receply_reservations SET cancel_requested_at = now(), cancel_request_turn = turn, cancel_request_conversation = conv, updated_at = now() WHERE id = hit.id;
    RETURN jsonb_build_object('ok', false, 'reason', 'confirm_needed',
      'message', 'Nothing is cancelled yet. Found booking ' || hit.ticket || ': room ' || hit.room_number || ', ' || hit.check_in || ' to ' || hit.check_out ||
                 coalesce(', ' || hit.guests_count || ' guest(s)', '') || ', in the name of ' || btrim(coalesce(hit.first_name, '') || ' ' || coalesce(hit.last_name, '')) ||
                 '. Show these details to the guest and ask them to confirm the cancellation. Call "Confirm Cancellation" only after their next message confirms; until that tool says CANCELLED, the booking stays active.');
  END IF;
  UPDATE receply_reservations SET status = 'cancelled', cancelled_at = now(), updated_at = now() WHERE id = hit.id;
  SELECT * INTO c FROM receply_clients WHERE account_id = acct;
  RETURN jsonb_build_object('ok', true, 'reservation_id', hit.id, 'ticket', hit.ticket, 'calendar_event_id', coalesce(hit.calendar_event_id, ''),
    'guest', btrim(coalesce(hit.first_name, '') || ' ' || coalesce(hit.last_name, '')), 'first_name', hit.first_name, 'email', hit.guest_email,
    'room', hit.room_number, 'guests', hit.guests_count, 'check_in', hit.check_in, 'check_out', hit.check_out, 'language', coalesce(hit.language, CASE WHEN lower(coalesce(p->>'language', '')) IN ('sq', 'sr', 'en') THEN lower(p->>'language') END, 'en'),
    'channel', hit.channel, 'conversation_id', hit.conversation_id, 'account_id', acct, 'timezone', c.timezone,
    'hotel', c.public_name, 'owner_email', c.owner_email, 'alert_topic', c.alert_topic);
END $_$;


--
-- Name: receply_confirm_booking(jsonb); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.receply_confirm_booking(p jsonb) RETURNS jsonb
    LANGUAGE plpgsql
    AS $_$
DECLARE
  acct int  := receply_resolve_account(p);
  code text := upper(btrim(coalesce(p->>'hold_code', '')));
  conv int  := CASE WHEN p->>'conversation_id' ~ '^\d+$' THEN (p->>'conversation_id')::int END;
  em   text := CASE WHEN lower(btrim(coalesce(p->>'email', ''))) ~ '^[^@\s]+@[^@\s]+\.[^@\s]+$' THEN lower(btrim(p->>'email')) END;
  turn text := nullif(btrim(coalesce(p->>'turn', '')), '');
  r record; c record; g record; n int; tkt text;
BEGIN
  IF acct IS NULL THEN
    RETURN jsonb_build_object('ok', false, 'reason', 'no_account', 'message', 'This conversation is not linked to a registered hotel. Nothing was booked.');
  END IF;
  IF code = '' AND conv IS NULL AND em IS NULL THEN
    RETURN jsonb_build_object('ok', false, 'reason', 'missing_code', 'message', 'Nothing was booked: no prepared booking was identified. Call "Prepare Reservation" first, show the guest the summary, and after they confirm call "Book Reservation" with the guest''s email.');
  END IF;
  PERFORM receply_expire_holds(acct);
  SELECT x.* INTO r
    FROM receply_reservations x LEFT JOIN receply_guests gx ON gx.id = x.guest_id
   WHERE x.account_id = acct AND x.hold_code IS NOT NULL
     AND CASE WHEN code <> '' THEN x.hold_code = code
              WHEN conv IS NOT NULL THEN x.conversation_id = conv
              ELSE lower(gx.email) = em END
     AND (x.status = 'held'
          OR (x.status = 'confirmed' AND x.confirmed_at > now() - interval '30 minutes')
          OR (x.status = 'expired' AND x.updated_at > now() - interval '6 hours'))
   ORDER BY (x.status = 'held') DESC, x.id DESC
   LIMIT 1
   FOR UPDATE OF x;
  IF r.id IS NULL THEN
    RETURN jsonb_build_object('ok', false, 'reason', 'not_found', 'message', 'There is no prepared booking to confirm, so nothing was booked. Call "Prepare Reservation" with the guest''s details, show them the summary and ask them to confirm.');
  END IF;
  SELECT * INTO c FROM receply_clients WHERE account_id = acct;
  SELECT * INTO g FROM receply_guests WHERE id = r.guest_id;
  IF r.status = 'confirmed' THEN
    RETURN jsonb_build_object('ok', true, 'already', true, 'ticket', r.ticket, 'room', r.room_number, 'check_in', r.check_in, 'check_out', r.check_out,
      'message', 'This booking is already confirmed (ticket ' || r.ticket || ', room ' || r.room_number || ', ' || r.check_in || ' to ' || r.check_out || '). Do not book it again.');
  END IF;
  IF r.status <> 'held' THEN
    RETURN jsonb_build_object('ok', false, 'reason', 'expired', 'message', 'The prepared booking is no longer held (it expired after 30 minutes, or the room turned out to be taken). Nothing was booked. Call "Prepare Reservation" again and ask the guest to confirm the new summary.');
  END IF;
  IF turn IS NULL OR r.hold_turn = turn THEN
    RETURN jsonb_build_object('ok', false, 'reason', 'confirm_needed', 'message', 'Not booked: the guest has not answered the summary yet. Send them the summary, ask them to confirm, and call "Book Reservation" only after their next message clearly says yes.');
  END IF;
  IF em IS NOT NULL AND lower(coalesce(g.email, '')) <> em THEN
    RETURN jsonb_build_object('ok', false, 'reason', 'details_changed', 'message', 'Not booked: the prepared booking uses the email ' || coalesce(g.email, '(none)') || ', not ' || em || '. If the guest changed a detail, call "Prepare Reservation" again with the corrected details and show them the new summary.');
  END IF;
  UPDATE receply_clients SET next_booking_no = next_booking_no + 1 WHERE account_id = acct RETURNING next_booking_no - 1 INTO n;
  tkt := receply_new_ticket(acct);
  UPDATE receply_reservations
     SET status = 'confirmed', confirmed_at = now(), held_until = NULL, booking_no = n, ticket = tkt, updated_at = now()
   WHERE id = r.id;
  RETURN jsonb_build_object('ok', true, 'already', false, 'reservation_id', r.id, 'ticket', tkt, 'booking_no', n,
    'room', r.room_number, 'room_type', (SELECT room_type FROM receply_rooms WHERE account_id = acct AND room_number = r.room_number),
    'guests', r.guests_count, 'check_in', r.check_in, 'check_out', r.check_out, 'nights', r.check_out - r.check_in,
    'check_in_time', to_char(r.check_in_at AT TIME ZONE c.timezone, 'HH24:MI'), 'check_out_time', to_char(r.check_out_at AT TIME ZONE c.timezone, 'HH24:MI'),
    'check_in_at', to_char(r.check_in_at AT TIME ZONE 'UTC', 'YYYY-MM-DD"T"HH24:MI:SS"Z"'), 'check_out_at', to_char(r.check_out_at AT TIME ZONE 'UTC', 'YYYY-MM-DD"T"HH24:MI:SS"Z"'),
    'first_name', g.first_name, 'last_name', g.last_name, 'phone', g.phone, 'email', g.email, 'language', coalesce(r.language, 'en'),
    'channel', r.channel, 'conversation_id', r.conversation_id, 'account_id', acct, 'timezone', c.timezone,
    'hotel', c.public_name, 'owner_email', c.owner_email, 'alert_topic', c.alert_topic);
END $_$;


--
-- Name: receply_expire_holds(integer); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.receply_expire_holds(p_account integer DEFAULT NULL::integer) RETURNS integer
    LANGUAGE sql
    AS $$
  WITH x AS (
    UPDATE receply_reservations
       SET status = 'expired', held_until = NULL, updated_at = now(), note = coalesce(note || '; ', '') || 'hold expired unconfirmed'
     WHERE status = 'held' AND held_until < now() AND (p_account IS NULL OR account_id = p_account)
    RETURNING 1)
  SELECT count(*)::int FROM x
$$;


--
-- Name: receply_find_reservations(jsonb); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.receply_find_reservations(p jsonb) RETURNS jsonb
    LANGUAGE plpgsql STABLE
    AS $$
DECLARE
  acct int  := receply_resolve_account(p);
  tkt  text := upper(btrim(coalesce(p->>'ticket', '')));
  em   text := lower(btrim(coalesce(p->>'email', '')));
  ph   text := regexp_replace(coalesce(p->>'phone', ''), '\D', '', 'g');
  res  jsonb;
BEGIN
  IF acct IS NULL THEN RETURN jsonb_build_object('reservations', '[]'::jsonb, 'message', 'This conversation is not linked to a registered hotel.'); END IF;
  IF tkt = '' AND em = '' AND length(ph) < 8 THEN
    RETURN jsonb_build_object('reservations', '[]'::jsonb, 'message', 'Ask the guest for their ticket number, or the email or phone number used for the booking, then look again.');
  END IF;
  SELECT coalesce(jsonb_agg(x.o ORDER BY x.later, x.check_in), '[]'::jsonb) INTO res FROM (
    SELECT jsonb_build_object('ID', r.booking_no, 'Name', g.first_name, 'Surname', g.last_name, 'PhoneNumber', g.phone, 'Email', g.email,
             'DateofReservation', coalesce(r.check_in::text, '?') || ' to ' || coalesce(r.check_out::text, '?'), 'Guests', r.guests_count,
             'Ticket Number', CASE WHEN r.status = 'held' THEN '(not issued yet)' ELSE r.ticket END, 'RoomNumber', r.room_number,
             'Status', CASE WHEN r.status = 'held' THEN 'held - waiting for the guest to confirm' ELSE r.status END) AS o,
           (r.check_out IS NULL OR r.check_out < current_date) AS later, r.check_in
      FROM receply_reservations r LEFT JOIN receply_guests g ON g.id = r.guest_id
     WHERE r.account_id = acct AND r.status <> 'expired' AND (
           (tkt <> '' AND upper(r.ticket) = tkt)
        OR (em <> '' AND lower(g.email) = em)
        OR (length(ph) >= 8 AND right(g.phone_digits, 8) = right(ph, 8)))
     ORDER BY 2, 3 LIMIT 5) x;
  RETURN jsonb_build_object('reservations', res, 'message',
    CASE WHEN res = '[]'::jsonb THEN 'No reservation matches those details.' ELSE 'Only share these details with the guest they belong to.' END);
END $$;


--
-- Name: receply_import_reservation(jsonb); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.receply_import_reservation(p jsonb) RETURNS text
    LANGUAGE plpgsql
    AS $_$
DECLARE
  acct int  := (p->>'account_id')::int;
  room text := nullif(btrim(coalesce(p->>'room_number', '')), '');
  ci   date := CASE WHEN p->>'check_in'  ~ '^\d{4}-\d{2}-\d{2}' THEN left(p->>'check_in', 10)::date END;
  co   date := CASE WHEN p->>'check_out' ~ '^\d{4}-\d{2}-\d{2}' THEN left(p->>'check_out', 10)::date END;
  tkt  text := coalesce(nullif(upper(btrim(coalesce(p->>'ticket', ''))), ''), 'IMPORT-ROW-' || coalesce(p->>'sheet_row', '?'));
  em   text := nullif(lower(btrim(coalesce(p->>'email', ''))), '');
  ev   text := nullif(btrim(coalesce(p->>'calendar_event_id', '')), '');
  st   text; g bigint; bad_room text;
BEGIN
  IF EXISTS (SELECT 1 FROM receply_reservations WHERE account_id = acct AND ticket = tkt) THEN RETURN 'already imported'; END IF;
  -- A room that is not one of the hotel's room numbers (2026-10-01: "Family Suite") cannot be protected against
  -- double bookings, and the database refuses it (receply_reservations_room_fk): keep the row as incomplete,
  -- without a room, and say in the note which room text has to be resolved by hand.
  IF room IS NOT NULL AND NOT EXISTS (SELECT 1 FROM receply_rooms WHERE account_id = acct AND room_number = room) THEN
    bad_room := room; room := NULL;
  END IF;
  st := CASE WHEN room IS NULL OR ci IS NULL OR co IS NULL OR co <= ci OR ev IS NULL THEN 'incomplete'
             WHEN p->>'event_state' = 'missing' THEN 'cancelled'
             ELSE 'confirmed' END;
  IF em IS NOT NULL THEN
    INSERT INTO receply_guests (account_id, first_name, last_name, phone, email) VALUES (acct, p->>'first_name', p->>'last_name', p->>'phone', em)
    ON CONFLICT (account_id, lower(email)) WHERE coalesce(email, '') <> '' DO UPDATE SET updated_at = now() RETURNING id INTO g;
  ELSIF coalesce(p->>'first_name', '') || coalesce(p->>'last_name', '') || coalesce(p->>'phone', '') <> '' THEN
    INSERT INTO receply_guests (account_id, first_name, last_name, phone) VALUES (acct, p->>'first_name', p->>'last_name', p->>'phone') RETURNING id INTO g;
  END IF;
  BEGIN
    INSERT INTO receply_reservations (account_id, booking_no, ticket, guest_id, room_number, check_in, check_out, status, calendar_event_id,
                                      conversation_id, whatsapp_phone, source, note, cancelled_at)
    VALUES (acct, CASE WHEN p->>'booking_no' ~ '^\d+$' THEN (p->>'booking_no')::int END, tkt, g, room, ci, co, st, ev,
            CASE WHEN p->>'conversation_id' ~ '^\d+$' THEN (p->>'conversation_id')::int END, nullif(p->>'whatsapp_phone', ''),
            'sheet-import', 'imported from sheet row ' || coalesce(p->>'sheet_row', '?') ||
            CASE WHEN bad_room IS NOT NULL THEN ': room "' || bad_room || '" is not one of the hotel''s room numbers - set the right room' ELSE '' END,
            CASE WHEN st = 'cancelled' THEN now() END);
  EXCEPTION WHEN exclusion_violation THEN
    st := 'conflict';
    INSERT INTO receply_reservations (account_id, booking_no, ticket, guest_id, room_number, check_in, check_out, status, calendar_event_id,
                                      conversation_id, whatsapp_phone, source, note)
    VALUES (acct, CASE WHEN p->>'booking_no' ~ '^\d+$' THEN (p->>'booking_no')::int END, tkt, g, room, ci, co, st, ev,
            CASE WHEN p->>'conversation_id' ~ '^\d+$' THEN (p->>'conversation_id')::int END, nullif(p->>'whatsapp_phone', ''),
            'sheet-import', 'imported from sheet row ' || coalesce(p->>'sheet_row', '?') || ': overlaps another confirmed stay in room ' || room);
  END;
  RETURN st;
END $_$;


--
-- Name: receply_new_ticket(integer); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.receply_new_ticket(p_account integer) RETURNS text
    LANGUAGE plpgsql
    AS $$
DECLARE t text; tries int := 0;
BEGIN
  LOOP
    t := 'TKT-' || (100000000 + floor(random() * 900000000))::bigint;
    EXIT WHEN NOT EXISTS (SELECT 1 FROM receply_reservations WHERE account_id = p_account AND upper(ticket) = t);
    tries := tries + 1;
    IF tries > 50 THEN RAISE EXCEPTION 'could not find a free ticket number'; END IF;
  END LOOP;
  RETURN t;
END $$;


--
-- Name: receply_next_booking_ids(jsonb); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.receply_next_booking_ids(p jsonb) RETURNS TABLE(generated_id integer, generated_ticket text)
    LANGUAGE plpgsql
    AS $$
DECLARE acct int := receply_resolve_account(p); n int; t text; tries int := 0;
BEGIN
  IF acct IS NULL THEN RAISE EXCEPTION 'not a registered Receply client (account %, workflow %)', p->>'account_id', p->>'workflow_id'; END IF;
  UPDATE receply_clients SET next_booking_no = next_booking_no + 1 WHERE account_id = acct RETURNING next_booking_no - 1 INTO n;
  LOOP
    t := 'TKT-' || (100000000 + floor(random() * 900000000))::bigint;
    EXIT WHEN NOT EXISTS (SELECT 1 FROM receply_reservations WHERE account_id = acct AND upper(ticket) = t);
    tries := tries + 1;
    IF tries > 50 THEN RAISE EXCEPTION 'could not find a free ticket number'; END IF;
  END LOOP;
  RETURN QUERY SELECT n, t;
END $$;


--
-- Name: receply_pending_note(jsonb); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.receply_pending_note(p jsonb) RETURNS text
    LANGUAGE plpgsql
    AS $_$
DECLARE
  acct int := receply_resolve_account(p);
  conv int := CASE WHEN p->>'conversation_id' ~ '^\d+$' THEN (p->>'conversation_id')::int END;
  tz text; note text := ''; r record;
BEGIN
  IF acct IS NULL OR conv IS NULL THEN RETURN ''; END IF;
  PERFORM receply_expire_holds(acct);
  SELECT coalesce(timezone, 'Europe/Belgrade') INTO tz FROM receply_clients WHERE account_id = acct;
  FOR r IN SELECT x.*, g.first_name, g.last_name, g.email FROM receply_reservations x LEFT JOIN receply_guests g ON g.id = x.guest_id
            WHERE x.account_id = acct AND x.conversation_id = conv AND x.status = 'held' ORDER BY x.id DESC LIMIT 1 LOOP
    note := note || '- A ROOM IS HELD for this guest and waits for their confirmation; it is NOT booked yet: room ' || r.room_number || ', ' ||
            r.check_in || ' to ' || r.check_out || ' (' || (r.check_out - r.check_in) || ' night(s)), ' || coalesce(r.guests_count::text, '?') || ' guest(s), name ' ||
            btrim(coalesce(r.first_name, '') || ' ' || coalesce(r.last_name, '')) || ', confirmation email ' || coalesce(r.email, '-') || ', held until ' ||
            to_char(r.held_until AT TIME ZONE tz, 'HH24:MI') || '. If the guest''s message clearly confirms it, call "Book Reservation" now; it is booked only when that tool says CONFIRMED. If they want changes, call "Prepare Reservation" again.' || E'\n';
  END LOOP;
  FOR r IN SELECT x.*, g.first_name, g.last_name FROM receply_reservations x LEFT JOIN receply_guests g ON g.id = x.guest_id
            WHERE x.account_id = acct AND x.cancel_request_conversation = conv AND x.status = 'confirmed'
              AND x.cancel_requested_at > now() - interval '30 minutes' ORDER BY x.cancel_requested_at DESC LIMIT 1 LOOP
    note := note || '- A CANCELLATION WAS REQUESTED and waits for the guest''s confirmation; the booking is NOT cancelled yet: ticket ' || r.ticket || ', room ' ||
            r.room_number || ', ' || r.check_in || ' to ' || r.check_out || ', name ' || btrim(coalesce(r.first_name, '') || ' ' || coalesce(r.last_name, '')) ||
            '. If the guest''s message confirms the cancellation, call "Confirm Cancellation" now with ticket ' || r.ticket || '; it is cancelled only when that tool says CANCELLED.' || E'\n';
  END LOOP;
  RETURN btrim(note, E'\n');
END $_$;


--
-- Name: receply_prepare_booking(jsonb); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.receply_prepare_booking(p jsonb) RETURNS jsonb
    LANGUAGE plpgsql
    AS $_$
DECLARE
  acct int := receply_resolve_account(p);
  fn   text := nullif(btrim(coalesce(p->>'first_name', '')), '');
  ln   text := nullif(btrim(coalesce(p->>'last_name', '')), '');
  ph   text := nullif(btrim(coalesce(p->>'phone', '')), '');
  em   text := nullif(lower(btrim(coalesce(p->>'email', ''))), '');
  gs   int  := CASE WHEN btrim(coalesce(p->>'guests', '')) ~ '^\d{1,3}$' THEN btrim(p->>'guests')::int END;
  room text := nullif(btrim(coalesce(p->>'room_number', '')), '');
  ci   date := CASE WHEN p->>'check_in'  ~ '^\d{4}-\d{2}-\d{2}' THEN left(p->>'check_in', 10)::date END;
  co   date := CASE WHEN p->>'check_out' ~ '^\d{4}-\d{2}-\d{2}' THEN left(p->>'check_out', 10)::date END;
  lang text := CASE WHEN lower(coalesce(p->>'language', '')) IN ('sq', 'sr', 'en') THEN lower(p->>'language') ELSE 'en' END;
  tin  text := CASE WHEN p->>'check_in_time'  ~ '^\d{1,2}:\d{2}$' THEN p->>'check_in_time'  ELSE '14:00' END;
  tout text := CASE WHEN p->>'check_out_time' ~ '^\d{1,2}:\d{2}$' THEN p->>'check_out_time' ELSE '11:00' END;
  conv int  := CASE WHEN p->>'conversation_id' ~ '^\d+$' THEN (p->>'conversation_id')::int END;
  turn text := nullif(btrim(coalesce(p->>'turn', '')), '');
  missing text[] := '{}';
  tz text; today date; rm record; g bigint; code text; held timestamptz := now() + interval '30 minutes';
BEGIN
  IF acct IS NULL THEN
    RETURN jsonb_build_object('ok', false, 'reason', 'no_account', 'message', 'This conversation is not linked to a registered hotel, so nothing can be booked. Offer to connect the guest with a person.');
  END IF;
  SELECT coalesce(timezone, 'Europe/Belgrade') INTO tz FROM receply_clients WHERE account_id = acct;
  today := (now() AT TIME ZONE tz)::date;
  IF fn IS NULL THEN missing := missing || 'first name'::text; END IF;
  IF ln IS NULL THEN missing := missing || 'surname'::text; END IF;
  IF ph IS NULL OR length(regexp_replace(ph, '\D', '', 'g')) < 6 THEN missing := missing || 'phone number'::text; END IF;
  IF em IS NULL OR em !~ '^[^@\s]+@[^@\s]+\.[^@\s]+$' THEN missing := missing || 'a valid email address'::text; END IF;
  IF gs IS NULL OR gs < 1 THEN missing := missing || 'number of guests'::text; END IF;
  IF ci IS NULL THEN missing := missing || 'check-in date'::text; END IF;
  IF co IS NULL THEN missing := missing || 'check-out date'::text; END IF;
  IF room IS NULL THEN missing := missing || 'room'::text; END IF;
  IF turn IS NULL THEN missing := missing || 'the conversation turn (system)'::text; END IF;
  IF cardinality(missing) > 0 THEN
    RETURN jsonb_build_object('ok', false, 'reason', 'missing_details', 'message', 'Nothing is held yet. Still needed: ' || array_to_string(missing, ', ') || '. Ask the guest for what is missing.');
  END IF;
  -- seen in tests: the AI passed "Ana Krasniqi" as the first name AND "Krasniqi" as the surname
  IF right(lower(fn), length(ln) + 1) = ' ' || lower(ln) THEN
    RETURN jsonb_build_object('ok', false, 'reason', 'name_check', 'message', 'Nothing is held: the first name "' || fn || '" already contains the surname. Call "Prepare Reservation" again right away with first name "' || btrim(left(fn, length(fn) - length(ln) - 1)) || '" and surname "' || ln || '" - no need to ask the guest.');
  END IF;
  IF left(lower(ln), length(fn) + 1) = lower(fn) || ' ' THEN
    RETURN jsonb_build_object('ok', false, 'reason', 'name_check', 'message', 'Nothing is held: the surname "' || ln || '" already contains the first name. Call "Prepare Reservation" again right away with first name "' || fn || '" and surname "' || btrim(substr(ln, length(fn) + 2)) || '" - no need to ask the guest.');
  END IF;
  IF ci < today THEN
    RETURN jsonb_build_object('ok', false, 'reason', 'past_date', 'message', 'The check-in date ' || ci || ' is in the past (today is ' || today || '). Nothing is held. Ask the guest for the correct dates.');
  END IF;
  IF co <= ci THEN
    RETURN jsonb_build_object('ok', false, 'reason', 'bad_dates', 'message', 'The check-out date must be after the check-in date. Nothing is held. Ask the guest for the correct dates.');
  END IF;
  IF co - ci > 60 THEN
    RETURN jsonb_build_object('ok', false, 'reason', 'too_long', 'message', 'Stays longer than 60 nights cannot be booked in the chat. Nothing is held. Offer to connect the guest with a person.');
  END IF;
  SELECT * INTO rm FROM receply_rooms WHERE account_id = acct AND room_number = room AND active;
  IF rm.room_number IS NULL THEN
    RETURN jsonb_build_object('ok', false, 'reason', 'unknown_room', 'message', 'Room ' || room || ' does not exist at this hotel. Nothing is held. Use a room number from "Get row Information Hotel Rooms".');
  END IF;
  IF rm.persons IS NOT NULL AND gs > rm.persons THEN
    RETURN jsonb_build_object('ok', false, 'reason', 'too_many_guests', 'message', 'Room ' || room || ' takes at most ' || rm.persons || ' guest(s), and this booking is for ' || gs || '. Nothing is held. Suggest a room with enough places (see "Get row Information Hotel Rooms").');
  END IF;
  PERFORM receply_expire_holds(acct);
  LOOP
    code := 'H-' || upper(substr(md5(random()::text || clock_timestamp()::text), 1, 6));
    EXIT WHEN NOT EXISTS (SELECT 1 FROM receply_reservations WHERE account_id = acct AND hold_code = code);
  END LOOP;
  BEGIN
    -- A new preparation replaces this guest's earlier unconfirmed hold (changed dates, room or details).
    -- Inside this block: if the new hold fails, the earlier one is kept.
    UPDATE receply_reservations
       SET status = 'expired', held_until = NULL, updated_at = now(), note = coalesce(note || '; ', '') || 'replaced by a newer preparation'
     WHERE account_id = acct AND status = 'held'
       AND ((conv IS NOT NULL AND conversation_id = conv) OR guest_id IN (SELECT id FROM receply_guests WHERE account_id = acct AND lower(email) = em));
    INSERT INTO receply_guests (account_id, first_name, last_name, phone, email) VALUES (acct, fn, ln, ph, em)
    ON CONFLICT (account_id, lower(email)) WHERE coalesce(email, '') <> ''
    DO UPDATE SET first_name = EXCLUDED.first_name, last_name = EXCLUDED.last_name, phone = EXCLUDED.phone, updated_at = now()
    RETURNING id INTO g;
    -- the ticket column holds the hold code until confirmation issues the real ticket
    INSERT INTO receply_reservations (account_id, ticket, guest_id, room_number, check_in, check_out, check_in_at, check_out_at, status,
                                      guests_count, language, hold_code, hold_turn, held_until, conversation_id, channel, whatsapp_phone, source)
    VALUES (acct, code, g, room, ci, co, (ci + tin::time) AT TIME ZONE tz, (co + tout::time) AT TIME ZONE tz, 'held',
            gs, lang, code, turn, held, conv, nullif(p->>'channel', ''), nullif(p->>'whatsapp_phone', ''), 'ai');
  EXCEPTION WHEN exclusion_violation THEN
    RETURN jsonb_build_object('ok', false, 'reason', 'room_taken', 'message', 'Room ' || room || ' is already booked (or held for another guest) for part of ' || ci || ' to ' || co || '. Nothing is held. Check another suitable room with "Check Availability" and prepare again.');
  END;
  RETURN jsonb_build_object('ok', true, 'hold_code', code, 'room', room, 'room_type', rm.room_type, 'persons', rm.persons, 'guests', gs,
    'check_in', ci, 'check_out', co, 'nights', co - ci, 'check_in_time', tin, 'check_out_time', tout,
    'check_in_at', to_char((ci + tin::time) AT TIME ZONE tz AT TIME ZONE 'UTC', 'YYYY-MM-DD"T"HH24:MI:SS"Z"'),
    'check_out_at', to_char((co + tout::time) AT TIME ZONE tz AT TIME ZONE 'UTC', 'YYYY-MM-DD"T"HH24:MI:SS"Z"'),
    'name', fn || ' ' || ln, 'phone', ph, 'email', em, 'language', lang,
    'held_until_local', to_char(held AT TIME ZONE tz, 'HH24:MI'),
    -- every room number of the hotel (switched-off ones too): the calendar check refuses to guess about an
    -- entry during the stay that names none of them
    'all_rooms', (SELECT jsonb_agg(room_number ORDER BY room_number) FROM receply_rooms WHERE account_id = acct));
END $_$;


--
-- Name: receply_release_hold(jsonb); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.receply_release_hold(p jsonb) RETURNS text
    LANGUAGE sql
    AS $$
  UPDATE receply_reservations SET status = 'expired', held_until = NULL, updated_at = now(),
         note = coalesce(note || '; ', '') || coalesce(nullif(p->>'reason', ''), 'released')
   WHERE account_id = receply_resolve_account(p) AND hold_code = upper(btrim(coalesce(p->>'hold_code', ''))) AND status = 'held'
  RETURNING 'released'
$$;


--
-- Name: receply_resolve_account(jsonb); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.receply_resolve_account(p jsonb) RETURNS integer
    LANGUAGE sql STABLE
    AS $_$
  SELECT c.account_id FROM receply_clients c
   WHERE c.account_id = CASE WHEN p->>'account_id' ~ '^\d+$' THEN (p->>'account_id')::int END
  UNION ALL
  SELECT c.account_id FROM receply_clients c
   WHERE coalesce(p->>'account_id', '') !~ '^\d+$' AND c.workflow_id = nullif(p->>'workflow_id', '')
  LIMIT 1
$_$;


--
-- Name: skip_tool_call_rows(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.skip_tool_call_rows() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
BEGIN
  IF (jsonb_typeof(NEW.message->'tool_calls') = 'array'
      AND jsonb_array_length(NEW.message->'tool_calls') > 0)
     OR NEW.message->>'type' = 'tool' THEN
    RETURN NULL;
  END IF;
  RETURN NEW;
END; $$;


SET default_tablespace = '';

SET default_table_access_method = heap;

--
-- Name: n8n_chat_memory; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.n8n_chat_memory (
    id integer NOT NULL,
    session_id character varying(255) NOT NULL,
    message jsonb NOT NULL,
    created_at timestamp with time zone DEFAULT now()
);


--
-- Name: n8n_chat_memory_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.n8n_chat_memory_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: n8n_chat_memory_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.n8n_chat_memory_id_seq OWNED BY public.n8n_chat_memory.id;


--
-- Name: n8n_faq_memory; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.n8n_faq_memory (
    id integer NOT NULL,
    session_id character varying(255) NOT NULL,
    message jsonb NOT NULL
);


--
-- Name: n8n_faq_memory_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.n8n_faq_memory_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: n8n_faq_memory_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.n8n_faq_memory_id_seq OWNED BY public.n8n_faq_memory.id;


--
-- Name: receply_bookings; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.receply_bookings (
    account_id integer NOT NULL,
    event_id text NOT NULL,
    conversation_id integer,
    whatsapp_phone text,
    created_at timestamp with time zone DEFAULT now() NOT NULL
);


--
-- Name: receply_clients; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.receply_clients (
    account_id integer NOT NULL,
    business_name text NOT NULL,
    vertical text DEFAULT 'hotel'::text NOT NULL,
    sheet_id text NOT NULL,
    calendar_id text NOT NULL,
    workflow_id text,
    webhook_path text,
    timezone text DEFAULT 'Europe/Belgrade'::text NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    office_open text DEFAULT '08:00'::text NOT NULL,
    office_close text DEFAULT '20:00'::text NOT NULL,
    office_days text DEFAULT '1-7'::text NOT NULL,
    owner_email text,
    alert_topic text,
    next_booking_no integer DEFAULT 1 NOT NULL,
    sheet_synced_at timestamp with time zone,
    sheet_sync_error text,
    mirror_hash text,
    public_name text
);


--
-- Name: TABLE receply_clients; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON TABLE public.receply_clients IS 'One row per onboarded client. sheet_id/calendar_id are UNIQUE: sharing either across two accounts would let one business read and overwrite another''s bookings and customer records.';


--
-- Name: COLUMN receply_clients.office_open; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.receply_clients.office_open IS 'Local time a human starts answering (HH:MM)';


--
-- Name: COLUMN receply_clients.office_close; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.receply_clients.office_close IS 'Local time a human stops answering (HH:MM); if < open, treated as crossing midnight';


--
-- Name: COLUMN receply_clients.office_days; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.receply_clients.office_days IS 'ISO weekdays a human is available, e.g. 1-5 for Mon-Fri, 1-7 for every day';


--
-- Name: COLUMN receply_clients.owner_email; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.receply_clients.owner_email IS 'Where this client''s escalations and booking notifications are emailed (the operator is copied on escalations).';


--
-- Name: COLUMN receply_clients.alert_topic; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.receply_clients.alert_topic IS 'ntfy topic for this client''s phone alerts. NULL = the operator topic.';


--
-- Name: COLUMN receply_clients.next_booking_no; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.receply_clients.next_booking_no IS 'Next booking number (the old sheet ID column), handed out by receply_next_booking_ids().';


--
-- Name: COLUMN receply_clients.sheet_sync_error; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.receply_clients.sheet_sync_error IS 'Last Sheet Sync problem for this client (NULL = fine). Alerts fire when it changes.';


--
-- Name: COLUMN receply_clients.mirror_hash; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.receply_clients.mirror_hash IS 'Hash of the reservations last written to the read-only Sheet tab (skip rewrites when unchanged).';


--
-- Name: COLUMN receply_clients.public_name; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.receply_clients.public_name IS 'The hotel''s name as guests know it, used in confirmation emails. NULL = emails use neutral wording.';


--
-- Name: receply_guests; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.receply_guests (
    id bigint NOT NULL,
    account_id integer NOT NULL,
    first_name text,
    last_name text,
    phone text,
    phone_digits text GENERATED ALWAYS AS (NULLIF(regexp_replace(COALESCE(phone, ''::text), '\D'::text, ''::text, 'g'::text), ''::text)) STORED,
    email text,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    updated_at timestamp with time zone DEFAULT now() NOT NULL
);


--
-- Name: TABLE receply_guests; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON TABLE public.receply_guests IS 'Guests (customers) per client, one row per email address.';


--
-- Name: receply_guests_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.receply_guests_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: receply_guests_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.receply_guests_id_seq OWNED BY public.receply_guests.id;


--
-- Name: receply_message_log; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.receply_message_log (
    id bigint NOT NULL,
    account_id integer,
    conversation_id integer,
    channel text,
    sender_phone text,
    customer_message text,
    ai_response text,
    is_error boolean DEFAULT false NOT NULL,
    source text DEFAULT 'live'::text NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL
);


--
-- Name: TABLE receply_message_log; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON TABLE public.receply_message_log IS 'Every AI turn: what the guest wrote and what the AI answered (was the Sheet tab Conversation Logs).';


--
-- Name: receply_message_log_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.receply_message_log_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: receply_message_log_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.receply_message_log_id_seq OWNED BY public.receply_message_log.id;


--
-- Name: receply_reminders; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.receply_reminders (
    id bigint NOT NULL,
    account_id integer NOT NULL,
    kind text NOT NULL,
    event_id text NOT NULL,
    guest_name text,
    guest_phone text,
    room text,
    checkin_at timestamp with time zone NOT NULL,
    status text DEFAULT 'pending'::text NOT NULL,
    detail text,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    sent_at timestamp with time zone,
    conversation_id integer,
    CONSTRAINT receply_reminders_status_check CHECK ((status = ANY (ARRAY['pending'::text, 'sent'::text, 'skipped'::text, 'failed'::text])))
);


--
-- Name: receply_reminders_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.receply_reminders_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: receply_reminders_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.receply_reminders_id_seq OWNED BY public.receply_reminders.id;


--
-- Name: receply_reservations; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.receply_reservations (
    id bigint NOT NULL,
    account_id integer NOT NULL,
    booking_no integer,
    ticket text NOT NULL,
    guest_id bigint,
    room_number text,
    check_in date,
    check_out date,
    check_in_at timestamp with time zone,
    check_out_at timestamp with time zone,
    status text DEFAULT 'confirmed'::text NOT NULL,
    calendar_event_id text,
    conversation_id integer,
    channel text,
    whatsapp_phone text,
    source text DEFAULT 'ai'::text NOT NULL,
    note text,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    updated_at timestamp with time zone DEFAULT now() NOT NULL,
    cancelled_at timestamp with time zone,
    guests_count integer,
    language text,
    hold_code text,
    hold_turn text,
    held_until timestamp with time zone,
    confirmed_at timestamp with time zone,
    cancel_requested_at timestamp with time zone,
    cancel_request_turn text,
    cancel_request_conversation integer,
    CONSTRAINT receply_reservations_confirmed_complete CHECK (((status <> ALL (ARRAY['held'::text, 'confirmed'::text])) OR ((room_number IS NOT NULL) AND (check_in IS NOT NULL) AND (check_out IS NOT NULL) AND (check_out > check_in)))),
    CONSTRAINT receply_reservations_guests_count_check CHECK (((guests_count IS NULL) OR (guests_count > 0))),
    CONSTRAINT receply_reservations_status_check CHECK ((status = ANY (ARRAY['held'::text, 'confirmed'::text, 'cancelled'::text, 'expired'::text, 'conflict'::text, 'incomplete'::text])))
);


--
-- Name: TABLE receply_reservations; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON TABLE public.receply_reservations IS 'Reservations. status: held (prepared, waiting for the guest''s yes in a later message; blocks the room for 30 min) | confirmed | cancelled | expired (a hold that lapsed, was replaced, or hit a calendar entry) | conflict (imported, overlapped a confirmed one) | incomplete (imported, missing dates/room/calendar event).';


--
-- Name: receply_reservations_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.receply_reservations_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: receply_reservations_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.receply_reservations_id_seq OWNED BY public.receply_reservations.id;


--
-- Name: receply_rooms; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.receply_rooms (
    account_id integer NOT NULL,
    room_number text NOT NULL,
    room_type text,
    persons integer,
    description text,
    extra jsonb DEFAULT '{}'::jsonb NOT NULL,
    active boolean DEFAULT true NOT NULL,
    sheet_row integer,
    updated_at timestamp with time zone DEFAULT now() NOT NULL,
    CONSTRAINT receply_rooms_persons_check CHECK (((persons IS NULL) OR (persons > 0)))
);


--
-- Name: TABLE receply_rooms; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON TABLE public.receply_rooms IS 'Rooms per client. Source of truth for the AI; edited by the owner in the Sheet tab RoomInformation and synced in.';


--
-- Name: n8n_chat_memory id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.n8n_chat_memory ALTER COLUMN id SET DEFAULT nextval('public.n8n_chat_memory_id_seq'::regclass);


--
-- Name: n8n_faq_memory id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.n8n_faq_memory ALTER COLUMN id SET DEFAULT nextval('public.n8n_faq_memory_id_seq'::regclass);


--
-- Name: receply_guests id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.receply_guests ALTER COLUMN id SET DEFAULT nextval('public.receply_guests_id_seq'::regclass);


--
-- Name: receply_message_log id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.receply_message_log ALTER COLUMN id SET DEFAULT nextval('public.receply_message_log_id_seq'::regclass);


--
-- Name: receply_reminders id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.receply_reminders ALTER COLUMN id SET DEFAULT nextval('public.receply_reminders_id_seq'::regclass);


--
-- Name: receply_reservations id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.receply_reservations ALTER COLUMN id SET DEFAULT nextval('public.receply_reservations_id_seq'::regclass);


--
-- Name: n8n_chat_memory n8n_chat_memory_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.n8n_chat_memory
    ADD CONSTRAINT n8n_chat_memory_pkey PRIMARY KEY (id);


--
-- Name: n8n_faq_memory n8n_faq_memory_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.n8n_faq_memory
    ADD CONSTRAINT n8n_faq_memory_pkey PRIMARY KEY (id);


--
-- Name: receply_bookings receply_bookings_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.receply_bookings
    ADD CONSTRAINT receply_bookings_pkey PRIMARY KEY (account_id, event_id);


--
-- Name: receply_clients receply_clients_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.receply_clients
    ADD CONSTRAINT receply_clients_pkey PRIMARY KEY (account_id);


--
-- Name: receply_guests receply_guests_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.receply_guests
    ADD CONSTRAINT receply_guests_pkey PRIMARY KEY (id);


--
-- Name: receply_message_log receply_message_log_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.receply_message_log
    ADD CONSTRAINT receply_message_log_pkey PRIMARY KEY (id);


--
-- Name: receply_reminders receply_reminders_account_id_kind_event_id_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.receply_reminders
    ADD CONSTRAINT receply_reminders_account_id_kind_event_id_key UNIQUE (account_id, kind, event_id);


--
-- Name: receply_reminders receply_reminders_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.receply_reminders
    ADD CONSTRAINT receply_reminders_pkey PRIMARY KEY (id);


--
-- Name: receply_reservations receply_reservations_no_double_booking; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.receply_reservations
    ADD CONSTRAINT receply_reservations_no_double_booking EXCLUDE USING gist (account_id WITH =, room_number WITH =, daterange(check_in, check_out, '[)'::text) WITH &&) WHERE ((status = ANY (ARRAY['held'::text, 'confirmed'::text])));


--
-- Name: receply_reservations receply_reservations_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.receply_reservations
    ADD CONSTRAINT receply_reservations_pkey PRIMARY KEY (id);


--
-- Name: receply_reservations receply_reservations_ticket_uniq; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.receply_reservations
    ADD CONSTRAINT receply_reservations_ticket_uniq UNIQUE (account_id, ticket);


--
-- Name: receply_rooms receply_rooms_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.receply_rooms
    ADD CONSTRAINT receply_rooms_pkey PRIMARY KEY (account_id, room_number);


--
-- Name: n8n_chat_memory_session_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX n8n_chat_memory_session_idx ON public.n8n_chat_memory USING btree (session_id, id);


--
-- Name: receply_clients_calendar_uniq; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX receply_clients_calendar_uniq ON public.receply_clients USING btree (calendar_id);


--
-- Name: receply_clients_sheet_uniq; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX receply_clients_sheet_uniq ON public.receply_clients USING btree (sheet_id);


--
-- Name: receply_guests_email_uniq; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX receply_guests_email_uniq ON public.receply_guests USING btree (account_id, lower(email)) WHERE (COALESCE(email, ''::text) <> ''::text);


--
-- Name: receply_guests_phone_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX receply_guests_phone_idx ON public.receply_guests USING btree (account_id, phone_digits);


--
-- Name: receply_message_log_acct_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX receply_message_log_acct_idx ON public.receply_message_log USING btree (account_id, created_at);


--
-- Name: receply_reminders_due_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX receply_reminders_due_idx ON public.receply_reminders USING btree (status, checkin_at);


--
-- Name: receply_reservations_checkin_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX receply_reservations_checkin_idx ON public.receply_reservations USING btree (account_id, check_in);


--
-- Name: receply_reservations_event_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX receply_reservations_event_idx ON public.receply_reservations USING btree (account_id, calendar_event_id);


--
-- Name: receply_reservations_hold_uniq; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX receply_reservations_hold_uniq ON public.receply_reservations USING btree (account_id, hold_code) WHERE (hold_code IS NOT NULL);


--
-- Name: n8n_chat_memory trg_skip_tool_calls; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER trg_skip_tool_calls BEFORE INSERT ON public.n8n_chat_memory FOR EACH ROW EXECUTE FUNCTION public.skip_tool_call_rows();


--
-- Name: receply_guests receply_guests_account_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.receply_guests
    ADD CONSTRAINT receply_guests_account_id_fkey FOREIGN KEY (account_id) REFERENCES public.receply_clients(account_id);


--
-- Name: receply_reservations receply_reservations_account_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.receply_reservations
    ADD CONSTRAINT receply_reservations_account_id_fkey FOREIGN KEY (account_id) REFERENCES public.receply_clients(account_id);


--
-- Name: receply_reservations receply_reservations_guest_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.receply_reservations
    ADD CONSTRAINT receply_reservations_guest_id_fkey FOREIGN KEY (guest_id) REFERENCES public.receply_guests(id);


--
-- Name: receply_reservations receply_reservations_room_fk; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.receply_reservations
    ADD CONSTRAINT receply_reservations_room_fk FOREIGN KEY (account_id, room_number) REFERENCES public.receply_rooms(account_id, room_number);


--
-- Name: receply_rooms receply_rooms_account_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.receply_rooms
    ADD CONSTRAINT receply_rooms_account_id_fkey FOREIGN KEY (account_id) REFERENCES public.receply_clients(account_id) ON DELETE CASCADE;


--
-- PostgreSQL database dump complete
--

\unrestrict kG3GgPzoxGxuEYAocSX2xvZOlrtVRgPGxolZhRUJ8jrlQtS701k1k196kGcmO6V

