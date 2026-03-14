
![Cursor Metro screenshot 1](docs/img1.jpeg)

**Cursor Metro** is a light-weight, open-source UX wrapper around the Cursor Agent CLI built for ‘Vibe Coding’


The name ‘Metro’ is inspired by small convenience stores like Tesco Metro, where you just want to pop in for a quick shop to pick up the basics, or perhaps a Subway or Metro getting from A-B quickly.

It addresses limitations and frustrations I have with coding in 2026:

1. Working with multiple projects and having multiple Cursor Windows and Terminals open.
2. Getting distracted with the code / Cursor taking up a lot of space on my screen requiring multiple monitors.
3. Losing track of what I was working on / getting lost in Agent Tabs.
4. Not being able to do some casual browsing yet wanting to remain productive, without Cursor taking up half my screen
5. Not being able to (easily) do everything in a single app for multiple projects.
6. Overcoming intertia being able to just create a new project and manage it from one single place. 
7. Having to type a prompt or command to do basic things like just commit and push / fix build

It is designed to be on your screen at all times unless you specifically minimize it. It can be  collapsed to a handy side panel that shows the progress of each of your agents.


![Cursor Metro screenshot 2](docs/im2.jpg)

![Cursor Metro screenshot 3](docs/img3.jpg)


It uses a simple Task based system.  Simply put, you create a bunch of tasks and delegate them to agents which you can track the status of in the sidebar until ready to review. Once happy enough you can complete those tasks to close out the issues.


![Cursor Metro screenshot 4](docs/img4.jpg)

It also has a simple terminal emulator, allowing you to build the project from within the same place as where you manage the agents and even this up for you if you don’t know how.


![Cursor Metro screenshot 5](docs/img5.jpg)

🏗️ Building

It is not quite ready yet, but you are welcome to build it yourself. You will to download:

* Cursor Agent CLI 
* XCode

You can run the shell script build-and-run.sh once XCode has been installed without having to open XCode

🧭 Road Map

* Creating/scaffolding new projects
* Remote Agents
* Claude Code interopability


