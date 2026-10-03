from fastapi import Depends, FastAPI, HTTPException, status
from sqlalchemy import select
from sqlalchemy.orm import Session

from app.db import Base, engine, get_db
from app.models import Task
from app.schemas import TaskCreate, TaskRead, TaskUpdate

Base.metadata.create_all(bind=engine)

app = FastAPI(
    title="SecureCloudOps API",
    version="0.1.0",
    description="Local workload for the SecureCloudOps cloud/security learning project.",
)


@app.get("/health")
def health() -> dict[str, str]:
    return {"status": "ok"}


@app.get("/tasks", response_model=list[TaskRead])
def list_tasks(db: Session = Depends(get_db)) -> list[Task]:
    return list(db.scalars(select(Task).order_by(Task.id)).all())


@app.post("/tasks", response_model=TaskRead, status_code=status.HTTP_201_CREATED)
def create_task(payload: TaskCreate, db: Session = Depends(get_db)) -> Task:
    task = Task(
    title=payload.title,
    description=payload.description,
    completed=False,
)
    db.add(task)
    db.commit()
    db.refresh(task)
    return task


@app.get("/tasks/{task_id}", response_model=TaskRead)
def get_task(task_id: int, db: Session = Depends(get_db)) -> Task:
    task = db.get(Task, task_id)
    if task is None:
        raise HTTPException(status_code=404, detail="Task not found")
    return task


@app.put("/tasks/{task_id}", response_model=TaskRead)
def update_task(
    task_id: int,
    payload: TaskUpdate,
    db: Session = Depends(get_db),
) -> Task:
    task = db.get(Task, task_id)
    if task is None:
        raise HTTPException(status_code=404, detail="Task not found")

    task.title = payload.title
    task.description = payload.description
    task.completed = payload.completed
    db.commit()
    db.refresh(task)
    return task


@app.delete("/tasks/{task_id}", status_code=status.HTTP_204_NO_CONTENT)
def delete_task(task_id: int, db: Session = Depends(get_db)) -> None:
    task = db.get(Task, task_id)
    if task is None:
        raise HTTPException(status_code=404, detail="Task not found")

    db.delete(task)
    db.commit()
