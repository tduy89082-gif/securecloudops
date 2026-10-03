up:
	docker compose up --build

down:
	docker compose down

down-clean:
	docker compose down -v

test:
	docker compose exec api pytest

logs:
	docker compose logs -f api
