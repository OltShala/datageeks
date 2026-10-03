--
-- PostgreSQL database dump
--

\restrict 5Aa50dNrf3aO5UhwejFvA6mq2kGnb4eW9YnCsLmgSrA2zFG1CsV6F8ySgxAvv4M

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
-- Data for Name: receply_rooms; Type: TABLE DATA; Schema: public; Owner: -
--

INSERT INTO public.receply_rooms (account_id, room_number, room_type, persons, description, extra, active, sheet_row, updated_at) VALUES (1, '101', 'Normal', 2, 'Cozy room with a queen bed and city view.', '{}', true, 2, '2026-09-30 19:14:16.014103+00');
INSERT INTO public.receply_rooms (account_id, room_number, room_type, persons, description, extra, active, sheet_row, updated_at) VALUES (1, '102', 'Normal', 2, 'Single room, perfect for business travelers.', '{}', true, 3, '2026-09-30 19:14:16.014103+00');
INSERT INTO public.receply_rooms (account_id, room_number, room_type, persons, description, extra, active, sheet_row, updated_at) VALUES (1, '103', 'Normal', 1, 'Single room, perfect for business travelers.', '{}', true, 4, '2026-09-30 19:14:16.014103+00');
INSERT INTO public.receply_rooms (account_id, room_number, room_type, persons, description, extra, active, sheet_row, updated_at) VALUES (1, '201', 'Normal', 2, 'Twin beds, balcony access, near the elevator.', '{}', true, 5, '2026-09-30 19:14:16.014103+00');
INSERT INTO public.receply_rooms (account_id, room_number, room_type, persons, description, extra, active, sheet_row, updated_at) VALUES (1, '202', 'Normal', 2, 'Queen bed, high floor with garden view.', '{}', true, 6, '2026-09-30 19:14:16.014103+00');
INSERT INTO public.receply_rooms (account_id, room_number, room_type, persons, description, extra, active, sheet_row, updated_at) VALUES (1, '301', 'Suite', 3, 'Master bedroom + living area, mini-bar included.', '{}', true, 7, '2026-09-30 19:14:16.014103+00');
INSERT INTO public.receply_rooms (account_id, room_number, room_type, persons, description, extra, active, sheet_row, updated_at) VALUES (1, '302', 'Suite', 4, 'Luxury suite with spa bath and panoramic view.', '{}', true, 8, '2026-09-30 19:14:16.014103+00');
INSERT INTO public.receply_rooms (account_id, room_number, room_type, persons, description, extra, active, sheet_row, updated_at) VALUES (1, '303', 'Suite', 2, 'Executive suite with dedicated workspace.', '{}', true, 9, '2026-09-30 19:14:16.014103+00');
INSERT INTO public.receply_rooms (account_id, room_number, room_type, persons, description, extra, active, sheet_row, updated_at) VALUES (1, '401', 'Normal', 2, 'Standard queen, recently renovated interior.', '{}', true, 10, '2026-09-30 19:14:16.014103+00');
INSERT INTO public.receply_rooms (account_id, room_number, room_type, persons, description, extra, active, sheet_row, updated_at) VALUES (1, '402', 'Normal', 3, 'Family room with one double and one single bed.', '{}', true, 11, '2026-09-30 19:14:16.014103+00');


--
-- PostgreSQL database dump complete
--

\unrestrict 5Aa50dNrf3aO5UhwejFvA6mq2kGnb4eW9YnCsLmgSrA2zFG1CsV6F8ySgxAvv4M

