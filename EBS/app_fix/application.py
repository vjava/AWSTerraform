from flask import Flask, jsonify

application = Flask(__name__)

@application.route("/")
def home():
    return jsonify({
        "status": "success",
        "message": "Hello from custom Python application on Elastic Beanstalk!",
        "framework": "Flask"
    })

if __name__ == "__main__":
    application.run(host="0.0.0.0", port=5000)
