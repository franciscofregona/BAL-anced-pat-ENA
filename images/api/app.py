from flask import Flask, jsonify
from random import randint
import pg8000
from os import environ

app = Flask(__name__)

@app.route('/randomName', methods=['GET'])
def getRandomName():
	first = ""
	last = ""
	response = {}
	firstIndex = randint(1,999)
	lastIndex = randint(1,1000)
	host = environ.get('POSTGRES_URL')
	firstSqlQuery = """select name from firstnames where pk = %d;""" % firstIndex
	lastSqlQuery = """ select last from lastnames where pk = %d;""" % lastIndex
	try:
		conn = pg8000.connect(user="postgres", password="holamundo", host=host, port = 5432, database = "postgres")
		cursor = conn.cursor()
		cursor.execute(firstSqlQuery)
		first = cursor.fetchone()[0]
		cursor.execute(lastSqlQuery)
		last = cursor.fetchone()[0]
	except (Exception) as error :
		print ("Error while connecting to PostgreSQL", error)
	finally:
		if(conn):
			cursor.close()
			conn.close()
	if (first):
		if (last):
			response = {
				'First name': first,
				'Lastname': last
			}
	return jsonify(response)


if __name__ == '__main__':
    app.run()
