from turtle import Turtle
import random

class Food(Turtle):

    def __init__(self):
        super().__init__()
        self.shape("square")
        self.penup()
        self.shapesize(stretch_len=1,stretch_wid=1)
        self.color("white")
        self.speed("fastest")
        self.refresh()

    def refresh(self):
        random_x = random.randrange(-280, 281, 20)
        random_y = random.randrange(-280, 281, 20)
        self.goto(random_x,random_y)