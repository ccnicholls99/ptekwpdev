Here you go, Craig — a **clean split diagram** showing the **App Lifecycle** and **Project Lifecycle** side‑by‑side.  
This is GitHub‑safe Mermaid, no HTML, no special characters, no parentheses that break rendering.

It gives contributors an instant mental model of the two independent cycles and how they relate.

---

# **PTEKWPDEV — Split Lifecycle Diagram**

```mermaid
flowchart LR

    %% ============================
    %% APP LIFECYCLE (LEFT SIDE)
    %% ============================

    subgraph APP_LIFECYCLE [App Lifecycle]
        A1[Clone Repo<br/>git clone ptekwpdev] --> A2[app_bootstrap<br/>Initialize app config<br/>Generate secrets]
        A2 --> A3[app_deploy<br/>Deploy templates<br/>Generate env<br/>Start core containers]
        A3 --> A4[App Ready]
    end

    %% ============================
    %% PROJECT LIFECYCLE (RIGHT SIDE)
    %% ============================

    subgraph PROJECT_LIFECYCLE [Project Lifecycle]
        P1[project_create<br/>Create metadata<br/>Update projects json] --> P2[project_deploy<br/>Scaffold repo<br/>Copy templates<br/>Provision dev sources]
        P2 --> P3[project_launch<br/>Start containers<br/>Logs and status]
        P3 --> P4[Project Ready]
    end

    %% ============================
    %% RELATIONSHIP BETWEEN CYCLES
    %% ============================

    A4 -. enables .-> P1
```

---

# **How to Use This Diagram**

### **Left Side: App Lifecycle**
Performed **rarely** — only when:

- setting up a new machine  
- resetting the entire environment  
- upgrading global templates  
- changing app‑level configuration  

It prepares:

- CONFIG_BASE  
- PROJECT_BASE  
- global Docker environment  
- app.json (the platform’s static configuration contract)

### **Right Side: Project Lifecycle**
Performed **frequently** — every time a contributor:

- creates a new project  
- provisions dev sources  
- deploys WordPress  
- starts or stops containers  

It prepares:

- project repo  
- project-level Docker config  
- project-level env  
- dev sources  
- WordPress runtime

### **The dotted arrow**
Indicates:

> The app lifecycle must be completed **once** before any project lifecycle can begin.

---

